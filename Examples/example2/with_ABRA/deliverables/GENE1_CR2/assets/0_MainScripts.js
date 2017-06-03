/* This is the primary Javascript library for MapLoc Reporter */

/*

Copyright 2016 Charles Tilford <podmail@biocode.fastmail.fm>

//Subject __must__ include 'Perl' to escape mail filters//

 http://mit-license.org/

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
  BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
  ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
  CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.

*/


var cxGlobal;
var firstCxObject;
var mlCxCounter = 0;
var mlTempStorage = {};

var debugPanel;

function debugMessage (txt, depth) {
    if (!debugPanel) {
        debugPanel = document.createElement('div');
        document.body.insertBefore(debugPanel, document.body.firstChild);
    }
    var line = document.createElement('div');
    var lead = "";
    if (!depth) depth = 0;
    for (var d = 0; d < depth; d++) { lead += "- "; }
    line.textContent = lead + "[DEBUG] " + txt;
    debugPanel.appendChild(line);
}

function unxss (txt) {
    /* Simplistic (possibly dangerously so) Anti-XSS text sanitization
       Designed for HTML attributes, with the intent of feeding either
       class or style attributes. Eliminates all but a handful of allowed
       characaters */
    if (typeof(txt) == 'undefined') return "";
    txt = txt.replace(/[^a-z0-9_:;\.\-# ]+/gi, '');
    return txt;

    // https://www.owasp.org/index.php/XSS_%28Cross_Site_Scripting%29_Prevention_Cheat_Sheet
}

function MapLocCxObject (obj, evt, cx) {
    this.obj = obj;
    this.evt = evt;
    this.cx  = cx;
    this.cat = '<br />';
    if (!firstCxObject) firstCxObject = cx;
}

mapLocMethods = new Object();
function registerMapLocDataMiner ( type, event, method ) {
    if (!type || !event || !method) return;
    if (!mapLocMethods[ event ])
        mapLocMethods[ event ] = new Object();
    if (!mapLocMethods[ event ][type])
        mapLocMethods[ event ][ type ] = new Array();
    mapLocMethods[ event ][ type ].push( method );
}

mapLocLinkers = new Object();
function registerMapLocLinker ( re, url ) {
    if (!re) return;
    mapLocLinkers[ re ] = [ new RegExp( re, 'gi' ), url ];
}

mapLocClassers = new Object();
function registerMapLocClasser ( re, cls, insensitive ) {
    if (!re) return;
    mapLocClassers[ re ] = insensitive ?
        [ new RegExp( re, 'i' ), cls ] : [ new RegExp( re ), cls ];
}

MapLocCxObject.prototype.dump = function (obj) {
    if (!obj) obj = this.obj;
    return this.cx.prettyJSON(obj);
}

MapLocCxObject.prototype.preDump = function (obj) {
    if (!obj) obj = this.obj;
    return "<pre>" + this.cx.prettyJSON(obj) + "</pre>";
}

MapLocCxObject.prototype.showTip = function () {
    var evt = this.evt;
    // this.cx.showInfoSpan(evt, this.tooltip(), evt.target || evt.srcElement);
    this.cx.showInfoSpan(evt, this.tooltip() );
    this.doLater();
}

MapLocCxObject.prototype.doLater = function () {
    var later = this.later || [];
    for (var l = 0; l < later.length; l++) {
        var ldat = later[l];
        ldat.cb.apply( this, ldat.args );
    }
    delete this.later;
}

MapLocCxObject.prototype.showDiv = function () {
    this.cx.showTooltipDiv(this.evt, this.tooltip());
    this.doLater();
}

MapLocCxObject.prototype.armEvent = function ( cxid ) {
    return "onclick='MLdoEvent(event)' onmouseover='MLdoEvent(event)' cxid='"+
        cxid+"'";
}

function MLdoEvent (evt) {
    if (!evt) evt = window.event;
    var targ = evt.target ? evt.target :
        evt.srcElement ? evt.srcElement : null;
    if (!targ) return;
    var cxid = targ.getAttribute('cxid');
    var cx   = CanvasXpress.getObject(cxid);
    var mlco = new MapLocCxObject( targ, evt, cx );
    if (targ.getAttribute('objid')) {
        mlco.showPopDiv( targ.getAttribute('objid'),
                         targ.getAttribute('objtype') );
    }
}

MapLocCxObject.prototype.showPopDiv = function ( objid, type ) {
    var evt   = this.evt;
    var cx    = this.cx;
    var cxid  = cx.target;
    if (!type) type = 'Pop';
    var pdat  = fetchSupportingData(type, objid) || {};
    var name  = pdat.name || pdat.text || "Object Report";
    var html  = "<h3>"+name+"</h3>";
    if (pdat.parent) {
        var pn = pdat.parent;
        pn = "<span class='faux moreinfo' objid='"+pn+"' "+
            this.armEvent(cxid)+">"+pn+"</span>"
        html += "<b>Parent:</b>"+pn+"<br />";
        if (pdat.root && pdat.root != pdat.parent) {
            var rn = pdat.root;
            rn = "<span class='faux moreinfo' objid='"+rn+"' "+
                this.armEvent(cxid)+">"+rn+"</span>"
            html += "<b>Root:</b>"+rn+"<br />";
        }
    }
    html += this.tagTable( pdat );
    html += "<i>DB ID = "+objid+"</i>";
    var trg = evt.target || evt.srcElement;
    if (evt.type == 'mouseover') {
        return cx.showInfoSpan( evt, html, trg);
    } else if (evt.type == 'click') {
        return cx.showTooltipDiv( evt, html, trg);
    }
}

MapLocCxObject.prototype.trackType = function () {
    var name = this.obj.trackType || this.obj.name;
    name = name.toLowerCase();
    if (/(polymorph|snp|vari)/.test(name)) {
        return 'polymorphism';
    } else if (/(align|rna|probe|oligo|exon)/.test(name)) {
        return 'alignment'
    } else if (/(feature|motif)/.test(name)) {
        return 'feature'
    }
    return this.obj.honorType ? name : 'unknown';    
}

MapLocCxObject.prototype.tooltip = function () {
    var miners = mapLocMethods[ 'mouseover' ];
    if (!miners) return this.defaultTip();
    var text = new Array();
    var data = this.obj.data;
    var dlen = data.length;
    var mMod = "";
    var maxLen = this.obj.briefLen || 4;
    if (dlen >= maxLen) {
        if (maxLen != 1) text.push("<i>"+dlen+" features at this location, zoom in for more details</i>");
        mMod = 'Brief';
    }
    var mineNames = [ this.trackType() + mMod, 'all' + mMod ];
    for (var mn = 0; mn < mineNames.length; mn++) {
        var minerName = mineNames[mn];
        var mineSub   = miners[ minerName ];
        if (!mineSub || mineSub.length == 0) continue;
        var tipTable;
        var ttHead = miners[ minerName + "Header"];
        if (ttHead) {
            // Method is set up to work totally as a table
            ttHead = ttHead[0]( this );
            tipTable = new Array();
        }
        for (var d = 0; d < dlen; d++) {
            var dTxt = new Array();
            for (var m = 0; m < mineSub.length; m++) {
                var t = mineSub[m]( this, d );
                if (t) dTxt.push(t);
            }
            if (tipTable) {
                tipTable = tipTable.concat(dTxt);
            } else {
                var subTxt = dTxt.join(this.cat) || this.basicId( d );
                if (d) subTxt = "<div class='break'>&nbsp;</div>" + subTxt;
                text.push(subTxt);
            }
        }
        if (tipTable) {
            text.push( "<table style='font-size:1.0em' class='tab'><tbody><tr><th>"+ttHead.join("</th><th>")+"</th></tr>"+this.slimTable( tipTable )  + "</tbody></table>");
        }
    }
    if (text.length == 0) return this.defaultTip();
    if (dlen == 1 && data[0].caption) text.unshift
       ("<span class='caption'>"+data[0].caption+"</span>");
    return text.join(this.cat) || "?";
}

MapLocCxObject.prototype.defaultTip = function () {
    var data = this.obj.data;
    var dl   = data.length;
    var text = new Array();
    for (var d = 0; d < dl; d++) {
        var bi = this.basicId(d);
        if (bi) text.push(bi);
    }
    var rv = text.join('<br />') || dl + " " + obj.name;
    return rv;
}


MapLocCxObject.prototype.varName = function ( dd ) {
    // dd is a particular variant record
    var au   = dd.accs;
    var text = new Array();
    text.push("<span class='coord'>"+dd.chrid+"</span>");
    if (au) {
        for (var acc in au) {
            var aname = acc;
            if (/^rs/.test(acc)) aname = "<a target='_blank' href='http://www.ncbi.nlm.nih.gov/projects/SNP/snp_ref.cgi?rs="+acc+"'>"+acc+"</a>";
            text.push( aname + " ("+au[acc].join(', ')+")");
        }
    }
    // if (text.length == 0) text.push(dd.id);
    return text;
}

MapLocCxObject.prototype.basicId = function ( d ) {
    var data = this.obj.data;
    if (d >= data.length) return "";
    if (data[d].id) {
        return "<b>"+this.swapLink(data[d].id)+"</b>";
    } else if (data[d].label) {
        return this.swapLink(data[d].label);
    } else if (data[d].name) {
        return this.swapLink(data[d].name);
    }
    return "";
}

MapLocCxObject.prototype.genericPopText = function ( d ) {
    var data = this.obj.data;
    if (d >= data.length) return "";
    var dd = data[d];
    if (!dd) return "<i>Unable to find object data!</i>";
    var text = [ this.basicId( d ) ];
    var links = this.hyperlinks( d );
    if (links) text.push( links );
    var pos = new Array();
    var pdat = dd.data;
    if (dd.len) pos.push( dd.len + "bp");
    if (pdat && pdat.length) pos.push("<b>"+dd.data[0][0] + "-" +
                                      dd.data[dd.data.length - 1][1]+"</b>");
    if (pos.length) text.push (pos.join(' '));
    if (dd.note) text.push("<i>"+dd.note+"</i>");
    var tabHTML = this.tagTable( dd );
    if (tabHTML) text.push( tabHTML );
    return text.join(this.cat);
}

MapLocCxObject.prototype.defaultTagHash = function ( ) {
    var gray = [ {
      value: "color: #aaa; font-size: 0.7em;",
      tagtoo: 1
    } ];
    var gcc = ' && ';
    var popConfig = { "DefaultCategoryUrl": {
            "url": "MLdoEvent objid='TAGVAL' objtype='Pop'"
        }};
    var catConfig = {
        "DefaultCategoryUrl": {
            "url": "MLdoEvent objid='TAGVAL' objtype='Cat'"
        }};
    return { 
        "use"   : { },
        "class" : { },
        "concat": { "URL Tag": gcc,
                    "Useful Tag": gcc,
                    "Concatenate Tag": gcc,
                    "Style Tag": gcc },
        "style" : { "URL Tag": gray,
                    "Useful Tag": gray,
                    "Concatenate Tag": gray, 
                    "Class Tag": gray, 
                    "Style Tag": gray },
        "urls":   { "Category": catConfig,
                    "Reference Population": popConfig,
                    "Normal Population": popConfig }
    };
}

MapLocCxObject.prototype.findUsefulTags = function ( obj, hash, depth ) {
    // depth is just used for debugging
    if (!depth) depth = 1;
    if (!hash) hash = this.defaultTagHash();
    if (!obj) return hash;
    if (obj['__tagRecursion']) return hash;
    obj['__tagRecursion'] = 1;
    var tags   = obj.tags;
    if (tags) {
        var ut = tags['Useful Tag'] || [];
        for (var u = 0; u < ut.length; u++) {
            var tag = ut[u];
            if (tag) hash.use[tag] = 1;
        }

        var con = tags['Concatenate Tag'] || [];
        for (var i = 0; i < con.length; i++) {
            var tag = con[i] || "";
            var hits = tag.match(/^\"(.+)\"\s+(.+)$/);
            if (hits && hits.length) {
                if (!hash.concat[hits[2]]) hash.concat[hits[2]] = hits[1];
            }
        }

        var urlt = tags['URL Tag'] || [];
        // debugMessage((obj.name || obj.id || obj.text) + ' has URL Tags: ' + urlt.join("\n"), depth);
        for (var j = 0; j < urlt.length; j++) {
            var data = this.parseMeta( urlt[j] );
            var tag = data.tag;
            if (!tag || !data.url) continue;
            if (!hash.urls[tag]) hash.urls[tag] = new Object();
            hash.urls[tag][data.url] = data;
            //debugMessage((obj.name || obj.id || obj.text) + " SET URL TAG:"+tag, depth);
        }
        
        var check = [ ['style', 'Style Tag'],
                      ['class', 'Class Tag'] ];
        for (var tc = 0; tc < check.length; tc++) {
            var cdat  = check[tc];
            var targ  = hash[ cdat[0] ];
            var found = tags[ cdat[1] ] || [];
            for (var j = 0; j < found.length; j++) {
                var data = this.parseMeta( found[j] );
                var tag  = data.tag;
                if (!tag || !data.value) continue;
                if (data.keep) data.keep = new RegExp( data.keep );
                if (!targ[tag]) targ[tag] = [];
                targ[tag].push(data);
            }
        }
    }
    // Get information from populations, if referenced:
    var pops = obj.freqs || {};
    for (var pid in pops) {
        this.findUsefulTags( fetchSupportingData('Pop', pid) || {},
                             hash, depth + 1 );
    }
    // Get useful tags from categories too
    // We put this here to let populations take precedence
    var cats = new Array();
    if (tags && tags["Category"]) cats = cats.concat(tags["Category"]);
    if (obj.cats) cats = cats.concat(obj.cats);
    for (var c = 0; c < cats.length; c++) {
        //debugMessage((obj.name || obj.id || obj.text) + ' has category ' + cats[c], depth);
        this.findUsefulTags( fetchSupportingData('Cat', cats[c]) || {},
                             hash, depth + 1 );
    }
    // var ut = new Array(); for (var t in hash.urls) { ut.push(t) }; debugMessage((obj.name || obj.id || obj.text) + ' has URL keys ' + ut.join(), depth);
    delete obj['__tagRecursion'];
    return hash;
}

MapLocCxObject.prototype.parseMeta = function ( txt ) {
    // parses out tags of the format key="value"
    var data = new Object();
    if (txt == null) return data;
    while (1) {
        var hits = txt.match(/(\S+)="([^\"]+)"/);
        if (!hits) break;
        var hit = hits[0];
        txt  = txt.replace(hit, "");
        data[hits[1]] = hits[2];
    }
    txt = txt.replace(/^\s+/, "");
    txt = txt.replace(/\s+$/, "");
    if (!data.value && txt != null) data.value = txt;
    return data;
}

MapLocCxObject.prototype.selectedTagTable = function ( obj, noBody ) {
    if (!obj) return "";
    var tags   = obj.tags;
    if (!tags) return "";
    var tagSelect = this.findUsefulTags( obj );
    return this.tagTable( obj, noBody, tagSelect );
}

MapLocCxObject.prototype.tagTable = function ( obj, noBody, tagSelect ) {
    if (!obj) return "";
    var tags = obj.tags;
    if (!tags) return "";
    var tabHTML = "";
    if (!noBody)
        tabHTML += "<table style='font-size:1.0em' class='tab tagtab'><tbody>";
    tabHTML += "<tr><th>Tag</th><th>Values</th></tr>";
    if (!tagSelect) { 
        tagSelect = this.findUsefulTags(obj);
        delete tagSelect['use'];
    }
    // var dbg = new Array(); for (var tag in tagSelect.use) { dbg.push(tag) }; return "<p>"+dbg.join('+')+"</p>";
    var urls  = tagSelect['urls']  || {};
    var stys  = tagSelect['style'] || {};
    var clss  = tagSelect['class'] || {};
    var table = new Array();
    for (var tag in tags) {
        if (tagSelect.use && !tagSelect.use[tag]) continue;
        var vals = tags[tag];
        if (tagSelect.concat) {
            var cc = tagSelect.concat[tag];
            if (cc != null) vals = [ vals.join(cc) ];
        }
        var metas   = [ clss[tag], stys[tag] ];
        var rows    = new Array();
        for (v = 0; v < vals.length; v++) {
            var tagMeta = [ ];
            var valMeta = [ 'tagval' ];
            var val  = vals[v];
            var row = rows[v] = [ [ tag ], [ val, 'tagval' ] ];
            // Check for meta rules on class and style:
            for (var m = 0; m < metas.length; m++) {
                var rm   = 1 + m;
                var mDat = metas[m] || [];
                for (var ts = 0; ts < mDat.length; ts++) {
                    var tdat = mDat[ts];
                    if (tdat.keep && !tdat.keep.test(val)) continue;
                    var st = tdat.value;
                    st     = st.replace('TAGVAL', val);
                    st     = unxss(st);
                    row[1][rm]  = row[1][rm] ? row[1][rm] + " " + st : st;
                    if (tdat.tagtoo) row[0][rm] = row[1][rm];
                }
            }
        }
        var tagUrls = urls[ tag ];
        if (tagUrls) {
            for (uv = 0; uv < rows.length; uv++) {
                var val      = rows[uv][1][0];
                var urlified = new Array();
                var done     = new Object();
                for (var ukey in tagUrls) {
                    var udat = tagUrls[ukey];
                    var url  = udat.url;
                    var name = udat.name || val;
                    url      = url.replace('TAGVAL', val);
                    if (done[url]++) continue;
                    var spec = url.match(/^MLdoEvent\s*(.+)$/);
                    if (spec && spec.length) {
                        var cxid = this.cx.target;
                        urlified.push
                            ("<span class='faux moreinfo' "+this.armEvent(cxid)+" "+
                             spec[1]+">"+name+"</span>");
                    } else {
                        urlified.push
                            ("<a target='_blank' href='"+url+"'>"+name+"</a>");
                    }
                }
                rows[uv][1][0] = urlified.join(', ');
            }
        }
        table = table.concat(rows);
    }
    if (!table.length) return "";
    tabHTML += this.slimTable( table );
    if (!noBody) tabHTML += "</tbody></table>";
    return tabHTML;
}

MapLocCxObject.prototype.hyperlinks = function ( d, extra ) {
    var toDo = extra || new Array();
    var data = this.obj.data;
    if (d < data.length && data[d]) {
        var dd = data[d];
        if (dd.links) toDo = toDo.concat( dd.links );
    }
    if (toDo.length == 0) return "";
    var anc = new Array();
    for (var l = 0; l < toDo.length; l++ ) {
        var name = "Link "+(l+1);
        var cls  = '';
        var url  = toDo[l];
        if (typeof(url) == 'object') {
            var uCon = url.constructor;
            if (uCon == Array) {
                if (url[1]) name = url[1];
                url = url[0];
            } else {
                anc.push("<i>JS Error! "+uCon+"</i>");
                continue;
            }
        }
        var lnk = "<a target='_blank' href='"+url+"'";
        lnk += ">"+name+"</a>";
        anc.push(lnk);
    }
    return anc.join(' | ');
}

MapLocCxObject.prototype.tableSorter = function ( a, b ) {
    // Just sorts a 2D array by the joined string of its members
    var at = makeStringForRow(a);
    var bt = makeStringForRow(b);
    return at < bt ? -1 : at > bt ? 1 : 0;
}

MapLocCxObject.prototype.featSorter = function ( a, b ) {
    return a.text < b.text ? -1 : a.text > b.text ? 1 : 0;
}

function makeStringForRow ( arr ) {
    var txt = "";
    var arrLen = arr.length;
    for (var r = 0; r < arrLen; r++) {
        txt += "\t" + arr[r][0];
    }
    return txt.toUpperCase();
}

MapLocCxObject.prototype.uniqueArray = function ( arr ) {
    var seen = new Object();
    var uniq = new Array();
    for ( var e = 0; e < arr.length; e++) {
        var txt = arr[e];
        if (!seen[txt]) {
            seen[txt] = 1;
            uniq.push(txt);
        }
    }
    return uniq;
}

var spanTok = '+SPAN+';
MapLocCxObject.prototype.slimTable = function ( table, firstCol ) {
    table = table.sort( this.tableSorter );
    var rowNum = table.length;
    var rowHTML = "";
    if (!firstCol) firstCol = 0;
    for (var r = 0; r < rowNum; r++) {
        rowHTML += "<tr>";
        var row = table[r];
        for (var c = firstCol; c < row.length; c++) {
            var cdat = row[c];
            var cell = cdat[0];
            if (cell == null) cdat[0] = cell = "";
            if (cdat[9] == null) cdat[9] = cdat.slice(0,8).join('+');
            var sameTok = cdat[9];
            // do not draw if this is a colspan token:
            if (cell == spanTok) continue;
            // do not draw if prior cell is the same:
            if (r && table[r-1][c][9] == sameTok) continue;
            rowHTML += "<td";
            var cls = new Array();
            if (cdat[1]) cls.push(cdat[1]);
            var pcs = this.patternClass(cell);
            if (pcs) cls.push(pcs);
            if (cdat[2]) rowHTML += " style='"+cdat[2]+"'";
            // Extra HTML attributes:
            if (cdat[3]) rowHTML += " "+cdat[3];
            var rspan = 1;
            for (var r2 = r+1; r2 < rowNum; r2++) {
                var nc = table[r2][c][9];
                if (nc == null) table[r2][c][9] = nc = 
                    table[r2][c].slice(0,4).join('+');
                if (nc == sameTok) {
                    rspan++;
                } else {
                    break;
                }
            }
            cspan = 1;
            for (var c2 = c+1; c2 < row.length; c2++) {
                var nc = table[r][c2][0];
                if (nc == null) table[r][c2][0] = nc = "";
                if (nc == spanTok) {
                    cspan++;
                } else {
                    break;
                }
            }
            if (rspan != 1) {
                rowHTML += " rowspan='"+rspan+"'";
                cls.push('vam'); // Align vertically
            }
            if (cspan != 1) {
                rowHTML += " colspan='"+cspan+"'";
            }
            if (cls.length) rowHTML += " class='"+cls.join(' ')+"'";
            rowHTML += ">"+this.swapLink(cell)+"</td>";
        }
        rowHTML += "</tr>";
    }
    return rowHTML;
}

MapLocCxObject.prototype.fracToGray = function ( fv ) {
    var rgb = Math.floor(0.5 + (1-fv) * 255);
    if (rgb < 0) {
        rgb = 0;
    } else if (rgb > 255) {
        rgb = 255;
    }
    var rsty = 'background-color: rgb('+rgb+','+rgb+','+rgb+')';
    if (fv >= 0.5) rsty += '; color: white; font-weight: bold;'; 
    return rsty;
}

MapLocCxObject.prototype.swapLink = function ( text ) {
    var swap = new Object();
    if (typeof(text) != 'string') return text;
    for (var r in mapLocLinkers) {
        var arr  = mapLocLinkers[r];
        var re   = arr[0];
        var url  = arr[1];
        if (!url) continue;
        var hits = text.match( re );
        if (!(hits && hits.length)) continue;
        for (var h = 0; h < hits.length; h++) {
            var hit = hits[0];
            if (!hit || swap[hit]) continue;
            var link = url;
            link     = link.replace('__ID__', hit);
            var num  = hit;
            num      = num.replace(/[^0-9]+/g, '');
            link     = link.replace('__NUM__', num);
            
            link = "<a target='_blank' href='"+link+"'>"+hit+"</a>";
            swap[ hit ] = link;
        }
    }
    return this.swapText( text, swap );
}

MapLocCxObject.prototype.patternClass = function ( text ) {
    var classes = new Array();
    if (typeof(text) != 'string') return '';
    for (var r in mapLocClassers) {
        var arr  = mapLocClassers[r];
        if (arr[0].test(text)) classes.push( arr[1] );
    }
    return classes.join(' ') || '';
}

MapLocCxObject.prototype.swapText = function ( text, hash ) {
    var swapA = 'FRONTSWAP';
    var swapB = 'SWAPBACK';
    var toSwap  = new Array();
    for (var input in hash) {
        var sw = swapA + toSwap.length + swapB;
        toSwap.push( hash[ input ] );
        var sRE = new RegExp(input, 'gi');
        text = text.replace( sRE, sw );
    }
    for (var s = toSwap.length - 1; s >= 0; s--) {
        var sRE = new RegExp(swapA + s + swapB, 'gi');
        text = text.replace( sRE, toSwap[s] );
    }
    return text;
}

MapLocCxObject.prototype.escAttr = function ( text ) {
    text = text.replace(/\'/g, '&apos;');
    text = text.replace(/\"/g, '&quot;');
    text = text.replace(/>/g, '&gt;');
    text = text.replace(/</g, '&lt;');
    return text;
}

MapLocCxObject.prototype.prettyLocation = function ( loc ) {
    var hack = loc + "";
    var bits = new Array();
    var chrdat = hack.match( /(.+):(\d+)/ );
    if (chrdat && chrdat.length) {
        var chr = chrdat[1];
        hack = chrdat[2];
        var blddat = chr.match( /(.+)\.(.+)/);
        if (blddat && blddat.length) {
            chr = blddat[1];
            var bld = blddat[2];
        }
        bits.push("Chr "+chr);
    }
    var comma = new Array();
    var digits = hack.split('');
    while (digits.length > 3) {
        var trip = [ digits.pop(), digits.pop(), digits.pop() ];
        comma.unshift( trip.reverse().join('') );
    }
    if (digits.length) comma.unshift( digits.join('') );
    bits.push(comma.join(','));
    return bits.join(' ') || loc;
};

MapLocCxObject.prototype.gravityPlot = function ( freq, alls, rcH ) {
    var id = "MlIntCanvas" + ++mlCxCounter;
    var anum = alls.length;
    var w = 400;
    var h = anum <= 2 ? 40 : w;
    var rv = "<canvas id='"+id+"' width='"+w+"' height='"+h+"'></canvas>";
    if (!this.later) this.later = [];
    this.later.push({
        "cb": this.makeGravityPlot,
        "args": [{
            "id": id,
            "h":h,
            "w":w,
            "freq":freq,
            "rch":rcH,
            "alls":alls
            }]
    });
    return rv;
}

MapLocCxObject.prototype.textColor = function ( text ) {
    var cdat = fetchSupportingData('Color', text) || "";
    var hit  = cdat.match(/(#[A-F0-9]+)/i);
    return hit ? hit[1] : '';
}

MapLocCxObject.prototype.makeGravityPlot = function ( dat ) {
    var id = dat.id;
    // alert( this.cx.getNewCanvasContext );
    var can = document.getElementById( id );
    if (!can) return;
    // if (!can.getContext) return;
    var alls = dat.alls.sort();
    var freq = dat.freq;
    var rcH  = dat.rch;
    var fH   = 10;
    var ctx  = this.cx.getNewCanvasContext( id );
    var tH   = 12;
    if (ctx.font) ctx.font = "bold "+tH+"px";
    var w    = dat.w;
    var h    = dat.h;
    var pad  = 16;
    var rad  = Math.floor(w/2) - pad;
    var cx   = Math.floor(w/2);
    var cy   = Math.floor(h/2);
    var pi   = Math.PI;
    var txtM = 1.2;
    var circ = 2 * Math.PI;
    var pnts = new Array();
    var aXY  = new Object();
    // Normalize the alleles and get a tally of overall abundance
    var normPid   = new Object();
    var totAllele = new Object();
    for (var pid in freq) {
        var aHash = freq[pid];
        var tot   = 0;
        var pHash = new Object();
        for (var all in aHash) {
            var f = aHash[all][0];
            if (f == null) {
                f = 1;
            } else if (f == 0) {
                continue;
            }
            tot += f;
            pHash[ all ] = f;
        }
        if (!tot) continue;
        normPid[pid] = pHash;
        for (var all in pHash) {
            // Normalize everything to sum to 1
            var f = pHash[ all ] / tot;
            pHash[ all ] = f;
            if (!totAllele[all]) totAllele[ all ] = 0;
            totAllele[ all ] += f;
        }
    }
    var allSort = new Array();
    for (var all in totAllele) {
        allSort.push( [all, totAllele[ all ]] );
    }
    allSort    = allSort.sort(function(a,b){return b[1]-a[1]});
    var aLen   = allSort.length;
    // Start the 'heaviest' allele on the bottom left edge
    var cStep  = circ / aLen;
    var cStart = 0 + pi/2 + cStep / 2;
    var maxY   = 0;
    for (var a = 0; a < aLen; a++) {
        var all  = allSort[a][0];
        var ang  = cStart - a * cStep;
        var x    = cx + Math.cos(ang) * rad;
        var y    = cy + Math.sin(ang) * rad;
        aXY[all] = ang;
        pnts.push([x,y,all]);
        if (maxY < y) maxY = y;
    }
    if (maxY) can.height = maxY + tH;
    for (var i = 0; i < aLen; i++) {
        var ix  = pnts[i][0];
        var iy  = pnts[i][1];
        var all = pnts[i][2];
        var ang = aXY[all];
        if (rcH) {
            if (rcH[all]) {
                all = rcH[all];
            } else {
                all = '?'+all+'?';
            }
        }
        var tsz = ctx.measureText(all);
        var tW  = tsz.width;
        ctx.fillStyle   = "rgb(255,0,0)";
        ctx.fillText(all, ix - tW * (1 - txtM * Math.cos(ang) )/ 2,
                     iy + tH * (1 + txtM * Math.sin(ang) )/ 2);
        
        if (aLen > 2) {
            // Line from point to center
            ctx.strokeStyle = 'rgba(0,0,255,0.2)';
            ctx.beginPath();
            ctx.moveTo(cx,cy);
            ctx.lineTo(ix,iy);
            ctx.stroke();
        }
        for (var j = 0; j < aLen; j++) {
            if (i == j) continue;
            // Line between pnts
            var jx = pnts[j][0];
            var jy = pnts[j][1];
            ctx.strokeStyle = 'rgba(0,0,255,0.2)';
            ctx.beginPath();
            ctx.moveTo(jx, jy);
            ctx.lineTo(ix, iy);
            ctx.stroke();
            var dx = jx - ix;
            var dy = jy - iy;
            for (var k = 0; k <= 10; k++) {
                // Tick marks
                ctx.fillStyle = 'rgba(0,0,0,1)';
                var kx = ix + k * dx / 10;
                var ky = iy + k * dy / 10;
                ctx.beginPath();
                ctx.arc(kx, ky, 1, 0, circ);
                ctx.fill();
            }
        }
    }

    var pids = new Array();
    for (var pid in normPid) {
        pids.push(pid);
    }
    var pNum = pids.length;
    ctx.fillStyle   = "rgb(200,200,200)";
    ctx.fillText("Allele distribution: "+pNum+" populations", 0, fH);

    ctx.globalAlpha = 0.2;
    for (var pid in normPid) {
        var psd   = fetchSupportingData( 'Pop', pid ) || {};
        var color = psd[ 'colorTag' ]  || "#aaa";
        ctx.fillStyle   = color; //"rgb(200,200,200,0.1)";
        
        var aHash = normPid[pid];
        var tot   = 0;
        var dx    = 0;
        var dy    = 0;
        for (var all in aHash) {
            var f   = aHash[all];
            var ang = aXY[all];
            dx     += f * Math.cos(ang);
            dy     += f * Math.sin(ang);
        }
        var x = cx + dx * rad;
        var y = cy + dy * rad;
        ctx.beginPath();
        ctx.arc(x, y, 5, 0, circ);
        ctx.fill();
    }
}


function eventToMLObject ( obj, evt, cx ) {
    if (!obj) return null;
    if (typeof(obj) != 'object') return null;
    var gt = cx.graphType || "Unknown";
    // Standardize how we handle the data
    if (gt == 'Network') {
        // Network object. We will wrap it up to look like a track
        if (obj.nodes) {
            obj = {
              data: obj.nodes,
              name: obj.nodes[0].type || "Unknown"
            };
        }
    } else if (gt == 'Genome') {
        // Genome track - get the data component
        obj = obj[0];
    } else {
        return null;
    }
    if (!obj) return null;
    if (!obj.data) return null;
    var mlco = new MapLocCxObject( obj, evt, cx );
    return mlco;
}

function locMouseOver ( obj, evt, cx ) {
    var mlco = eventToMLObject( obj, evt, cx );
    if (!mlco) return;
    mlco.showTip();
}

function locMouseClick ( obj, evt, cx ) {
    var mlco = eventToMLObject( obj, evt, cx );
    if (!mlco) return;
    mlco.showDiv();
}

function loadMinerHash (hash) {
    for (var event in hash) {
        var eH = hash[event];
        for (var type in eH) {
            registerMapLocDataMiner( type, event, eH[type] );
        }
    }
}

var MLsupportData = new Object();
function fetchSupportingData ( cat, key ) {
    if (!MLsupportData || !MLsupportData[ cat ]) return null;
    return MLsupportData[ cat ][ key ] || null;
}

// https://stackoverflow.com/questions/783661/log-to-firefox-error-console-from-javascript
function log(param){
    setTimeout(function(){
        throw new Error("Debug: "+param)
    },0)
}

var standardMapLocMiners = {
  mouseover: {
    polymorphismBriefHeader: function () {
        return ["Impact","Location"];
    },
    polymorphismBrief: function (mlco, d) {
        var data = mlco.obj.data;
        var dd   = data[d];
        var ids  = mlco.varName( dd );
        var row  = new Array();
        if (dd.impName) {
            row.push( [dd.impName, "Imp" + dd.impToken] );
        } else {
            row.push( ['?'] );
        }
        
        row.push( [ids.join('<br />')] );
        return row;
    },
    polymorphism: function (mlco, d) {
        var data = mlco.obj.data;
        var dd   = data[d];
        var text = mlco.varName( dd );
        if (dd.cats && dd.cats.length) {
            var catHtml = new Array();
            for (var f = 0; f < dd.cats.length; f++) {
                var cat = dd.cats[f];
                var csd = fetchSupportingData( 'Cat', cat ) || {};
                if (csd.colorTag) {
                    catHtml.push("<span style='color:"+csd.colorTag+
                                 "'>"+cat+"</span>");
                } else {
                    catHtml.push(cat);
                }
            }
            text.push( "<i>" + catHtml.join(', ') + "</i>");
        }
        var mafvar = new Array();
        if (dd.MAF) {
            if (dd.MAF == '-1') {
                mafvar.push('<i>Alleles specified without frequency</i>');
            } else {
                mafvar.push('MAF='+dd.MAF+'%');
            }
        }
        if (mafvar.length) {
            text.push(mafvar.join(', '));
        }
        if (dd.impName) {
            var vn = dd.impName;
            if (dd.impToken) 
                vn = "<span class='Imp"+dd.impToken+"'>"+vn+"</span>";
            text.push(vn);
        }
        var links = mlco.hyperlinks( d );
        if (links) text.push( links );

        var errs = new Array();
        var w = dd.w;
        var imps = dd.impact;
        var freq = dd.freqs;
        var allH = new Object();
        var rnas = new Array();
        var tabHTML = "";
        var rcH  = dd.revcom;
        if (rcH) {
            text.push("<i>Reported alleles are from -1 genomic strand</i>");
        }

        if (imps) {
            for (var r in imps) {
                rnas.push(r);
                for (var al in imps[r]['var']) {
                    allH[al] = 1;
                }
            }
            rnas = rnas.sort();
        }
        var pops = new Array();
        if (freq) {
            for (var pid in freq) {
                for (var al in freq[pid]) {
                    allH[al] = 1;
                }
                pops.push(pid);
            }
            pops = pops.sort();
        }
        var feat = dd.features || {};
        var feats = new Array();
        for (var fid in feat) {
            var fdat = fetchSupportingData('Feat', fid);
            if (fdat) feats.push( fdat );
        }

        var fNum = feats.length;
        if (fNum) {
            feats = feats.sort( mlco.featSorter );
            var ftxt = "<table style='font-size:0.8em'><tbody>";
            for (var f = 0; f < fNum; f++) {
                var fd = feats[ f ];
                ftxt += "<tr><td style='background-color:"+fd.color+"'>&nbsp;</td>";
                var nm = fd.name || fd.text || "";
                var tit = new Array();
                if (fd.name) tit.push("["+fd.text+"]");
                if (fd.com) tit.push(fd.com);
                if (nm.length > 25) {
                    tit.push(nm);
                    nm = nm.substring(0,25) + '&hellip;';
                }
                
                ftxt += "<td";
                if (tit.length) ftxt += " title='"+mlco.escAttr(tit.join(' '))+"'";
                ftxt += ">"+nm+"</td></tr>";
            }
            ftxt += "</tbody></table>";
            text.push( ftxt);
        }
    

        var alls = new Array();
        for (var a in allH) {
            alls.push(a);
        }
        var allLen  = alls.length;
        var allHead = "";
        if (allLen) {
            alls = alls.sort();
            for (var b = 0; b < allLen; b++) {
                var base = alls[b];
                var sty  = (rNum && base == imps[rnas[0]].ref) 
                    ? " style='color:green'" : "";
                var bLen = base.length;
                if (rcH) {
                    var rc = rcH[ base ];
                    if (rc) {
                        base = rc;
                    } else {
                        base = "?"+base+"?";
                    }
                }
                if (bLen > 20) {
                    base = bLen + "bp";
                } else if (base.length > 5) {
                    var bb = new Array();
                    for (var i = 0; i < base.length; i += 5) {
                        bb.push( base.substr(i,5) );
                    }
                    base = bb.join(' ');
                }
                allHead += "<th"+sty+">"+base+"</th>";
            }
        }

        var rNum = rnas.length;
        if (rNum) {
            var head = ['Impact', 'Prot', 'Nuc', 'RNA'];
            tabHTML += "<tr>"+allHead+"<th>"+head.join
                ("</th><th>")+"</th></tr>";
            var table = new Array();
            for (r = 0; r < rNum; r++) {
                var rid  = rnas[r];
                var rdat = fetchSupportingData('RNA', rid) || {};
                var rna  = rdat.acc;
                var imd  = imps[rid];
                if (imd.ERROR) errs = errs.concat(imd.ERROR);
                var adat = fetchSupportingData('Align', imd.align) || {};
                var cp   = imd.cdpos;
                var rtxt = rdat.name;
                var hb   = adat.howbad;
                if (hb == null) {
                    rtxt = "<span class='howbad' title='It is not known how well this position is aligned to the genome'>&Dagger;??%</span> " + rtxt;
                    hb = 100;
                } else if (hb) {
                    rtxt = "<span class='howbad' title='Not the best genomic location for this gene'>&Dagger;"+hb+
                        "%</span> " + rtxt;
                }
                var sorter = (hb || 100) / 1000;
                if (imd.note) {
                    rtxt += "<br /><span class='note'>"+imd.note+"</span>";
                }
                var impTok = imd.imp;
                sorter    += "\t"+impTok;
                var row = [ [impTok, "Imp"+impTok], 
                            [imd.protNom || imd.protPos, 'seq'],
                            [imd.nucNom || imd.nucPos, 'seq'],
                            [rtxt] ];

                for (var b = allLen -1; b >= 0; b--) {
                    var altxt  = "";
                    var base   = alls[b];
                    var vdat   = imd['var'][ base ] || [];
                    var codon  = vdat[0];
                    var blen   = base == '-' ? 0 : base.length;
                    if (codon) {
                        var chars = codon.split('');
                        var cl    = chars.length;
                        var aS    = cp - 1;
                        var aE    = aS + blen - 1;
                        var aIns  = -1;
                        if (!blen) {
                            aIns = aS;
                            aE = aS = -1;
                        }
                        for (var c = 0; c < cl; c++) {
                            if (c && !(c % 3)) altxt += ' ';
                            if (c == aS) altxt += "<span class='var'>";
                            if (c == aIns) altxt += "<span class='del'>-</span>";
                            altxt += chars[c];
                            if (c == aE) altxt += "</span>";
                        }
                        /*
                            if (cp) altxt += codon.substr(0, cp-1);
                        altxt += "<span class='var'>"+vdat[2]+"</span>";
                        var rss = cp + base.length - 1;
                        if (rss < codon.length) altxt +=
                            codon.substr(rss);
                            */
                        if (vdat[1]) altxt += "<div class='prt'>"+
                            vdat[1]+"</div>";
                    }
                    row.unshift( [altxt,'allele']  );
                }
                if (imd.impNote) {
                    row[0] = [ imd.impNote, 'note' ];
                    for (var b = 1; b < allLen; b++) {
                        row[b] = [spanTok];
                    }
                }
                row.unshift( [sorter] );
                table.push( row );
            }
            tabHTML += mlco.slimTable( table, 1 );
        }

        var classTagHash = new Object();
        var cats   = dd.cats || [];
        for (var ct = 0; ct < cats.length; ct++) {
            var cdat = fetchSupportingData('Cat', cats[ct]) || {};
            if (!cdat || !cdat.tags) continue;
            var ccls = cdat.tags['SNP Class Tag'] || [];
            for (var cl = 0; cl < ccls.length; cl++) {
                var v = ccls[cl];
                if (v) classTagHash[ v ] = 1;
            }
        }
        var classTags = new Array();
        for (var ct in classTagHash) {
            classTags.push(ct);
        }
        var okPids = dd.okPids;
        var colPad = 3;
        // colPad++ if (okPids);
        var pNum = pops.length;
        if (alls.length > 1 &&
            (pNum >= 10 || (alls.length == 2 && pNum >= 5))) {
            tabHTML += "<tr><td colspan='"+(allLen+colPad+1)+"'>";
            tabHTML += mlco.gravityPlot(freq, alls, rcH);
            tabHTML += "</td></tr>";
        }
        if (pNum) {
            var cxid = mlco.cx.target;
            tabHTML += "<tr>"+allHead+"<th>Class</th><th colspan='"+colPad+
            "'>Population</th></tr>";
            var table = new Array();
            var spanPad = [[spanTok],[spanTok]];
            for (p = 0; p < pNum; p++) {
                var pid  = pops[p];
                var pdat = fetchSupportingData('Pop', pid) || {};
                var ptag = pdat.tags || {};
                var par  = pdat.parent;
                var pname = (pdat.name || pop || "") + "";
                pname = pname.replace(/_/g, ' ');

                var pfrq = freq[pid];
                var row  = new Array();
                for (var b = 0; b < allLen; b++) {
                    var base = alls[b];
                    var fdat = pfrq[ base ];
                    var txt  = "";
                    var rcls = 0;
                    var rsty = 0;
                    var rtit = 0;
                    if (fdat) {
                        var fv = fdat[0];
                        if (fv === undefined || fv === '') {
                            rtit = "No frequency data available";
                            rcls = 'nofreq Bogus'+b+'_'+p;
                            if (fdat[1]) {
                                // No freq, but counts are available
                                txt = '?&nbsp;/&nbsp;'+fdat[1];
                                rtit += ", total count of "+fdat[1];
                            } else {
                                txt = '&#10003;'; // Check mark
                            }
                        } else {
                            rcls = 'freq';
                            var num = 1;
                            if (fdat[1]) {
                                num  = Math.floor(0.5 + fv * fdat[1]);
                                rtit = num+" out of "+fdat[1];
                            }
                            if (num) {
                                rsty = mlco.fracToGray( fv );
                                
                                txt = Math.floor(0.5 + fv * 100) + "";
                                // To help sort the table:
                                var sillyPad = 3 - txt.length;
                                for (var sp = 0; sp < sillyPad; sp++) {
                                    txt = " "+txt; }
                                txt += "%";
                                //txt += "="+sillyPad;
                            } else {
                                // Explicit zero count
                                txt  = "&Oslash;";
                                rcls = 'countzero';
                                rtit = 'Explicitly zero';
                                if (num) rtit += " out of "+num;
                            }
                        }
                    }
                    if (rtit) rtit = "title='"+mlco.escAttr(rtit)+"'";
                    row.push([txt, rcls, rsty, rtit]);
                }
                var sclH = new Object();
                for (var cti = 0; cti < classTags.length; cti++) {
                    var cln = ptag[classTags[cti]] || [];
                    for (var cn = 0; cn < cln.length; cn++) {
                        var v = cln[cn];
                        if (v) sclH[ v ] = 1;
                    }
                }
                var snpCls = new Array();
                for (var scl in sclH) {
                    var sty = fetchSupportingData('Color', scl) || "";
                    if (sty) {
                        snpCls.push("<span style='"+sty+"'>"+scl+"</span>");
                    } else {
                        snpCls.push(scl);
                    }
                }
                snpCls = snpCls.sort();
                row.push([snpCls.join(',')]);
                var popSty = new Array();
                if (pdat.colorTag) popSty.push('color: '+pdat.colorTag);
                
                var rCls = 'moreinfo';
                if (okPids) {
                    var ok = okPids[pid];
                    if (!ok) {
                        rCls += ' filtFail';
                    } else if (ok < 0) {
                        rCls += ' filtOk';
                    } else {
                        rCls += ' filtPass';
                    }
                }
                var xtra = mlco.armEvent(cxid) + " objid='"+pid+"'";
                row.push([ pname, rCls, popSty.join('; '), xtra ]);
                row = row.concat( spanPad );
                table.push(row);
            }
            tabHTML += mlco.slimTable( table );
        }
        if (imps && imps.ERROR) errs = errs.concat(imps.ERROR);

        if (tabHTML) text.push
            ("<table style='font-size:1.0em' class='tab'><tbody>" +
             tabHTML + "</tbody></table>");
        var tagHtml = mlco.selectedTagTable( dd );
        if (tagHtml) text.push(tagHtml);
        
        if (errs.length) text.push
            ("<div class='err'><b>Errors reported!</b><ul><li>"+
             mlco.uniqueArray(errs).join("</li><li>") + "</li></ul></div>");
        // text.push( mlco.preDump(dd) );
        // text.push( mlco.preDump(table) );
        // return rowNum + mlco.preDump(table);
        return text.join(mlco.cat);
    },
    alignment: function (mlco, d) {
        var data = mlco.obj.data;
        var dd   = data[d];
        var text = new Array();
        var tags = dd.tags || {};
        var bt   = mlco.basicId(d);
        if ( bt ) text.push( bt );
        var links = new Array();
        if (dd.llid) links.push
            ( ['http://www.ncbi.nlm.nih.gov/sites/varvu?gene='+dd.llid, 
               'VarViewer' ],
              ['http://www.ncbi.nlm.nih.gov/projects//SNP/snp_ref.cgi?locusId='
               +dd.llid, 'dbSNP' ] );

        if ( tags.Description && tags.Description.length ) {
            text.push( "<i>"+mlco.swapLink(tags.Description[0])+"</i>" );
        }
        if (dd.gene) {
            var cxid  = mlco.cx.target;
            text.push("<b>Gene:</b> <span class='faux moreinfo' objid='"+
                      dd.gene+"' objtype='Gene'"+
                      mlco.armEvent(cxid)+">"+dd.gene+"</span>");
        }

        var lbits = new Array();
        if ( tags.Taxa ) lbits.push( tags.Taxa[0] );
        if ( tags.Symbol && tags.Symbol[0])
            lbits.push( "<b>"+tags.Symbol[0]+"</b>" );
        if ( tags.LocusID ) lbits.push( mlco.swapLink(tags.LocusID[0]) );
        if (lbits.length != 0) text.push(lbits.join(' ' ));
        
        var pbits = new Array();
        if (dd.aacoord) {
            pbits.push( mlco.prettyLocation(dd.aacoord[0])+"&ndash;"+
                        mlco.prettyLocation(dd.aacoord[1])+"aa");
        }
        if (dd.phase != null) pbits.push( "Phase " + dd.phase);
        if (pbits.length != 0) text.push(pbits.join(', ' ));
        
        var sc = dd.score;
        if (sc) {
            sc = "Score "+dd.score+"%";
            var hb   = dd.howbad;
            var mcol = hb < 1 ? "#060" : hb < 3 ? "#f90" : "#f00";
            var mtxt = hb ? hb + "% worse than best" : "Best genome match";
            if (hb) mcol += ';font-weight:bold';
            text.push(sc + " = <span style='color:"+mcol+"'>"+mtxt+"</span>");
        }
        var ty = dd.type;
        if (ty) {
            var sty = fetchSupportingData('Color', ty) || "";
            text.push("Type: <span style='"+sty+"'>"+ty+"</span>");
        }
        var linkText = mlco.hyperlinks( d, links );
        if (linkText) text.push( linkText );
        if (dd.coords) {
            var typ = dd.type || 'HSP';
            var crd = dd.coords;
            var chrs = new Array();
            for (var chr in crd) {
                chrs.push(chr);
            }
            chrs = chrs.sort();
            for (c = 0; c < chrs.length; c++) {
                var chr = chrs[c];
                text.push("<b>Chromosome "+chr+":</b>");
                var td = new Array();
                for (var r = 0; r < crd[chr].length; r++) {
                    var dat = crd[chr][r];
                    var row = [ [dat[0]], [mlco.prettyLocation(dat[1])+' - '+mlco.prettyLocation(dat[2])], [mlco.prettyLocation(dat[2] - dat[1] + 1)], [dat[3]], [dat[4]] ];
                    td.push(row);
                }
                text.push("<table style='font-size:1.0em' class='tab'><tbody><tr><th>Build</th><th>Coordinates</th><th>Length</th><th>"+typ+"</th><th>Strand</th></tr>" + mlco.slimTable( td ) + "</tbody></table>");
            }
        }
        if (dd.source) text.push("<span style='font-size:0.8em'>Source: "
                                 + dd.source + "</span>");
        return text.join(mlco.cat);
    },
    featureBriefHeader: function (mlco, d) {
        return ['Size', 'Name'];
    },
    featureBrief: function (mlco, d) {
        var data = mlco.obj.data;
        var dd   = data[d];
        var ids  = mlco.varName( dd );
        var row  = [ [dd.len], [ mlco.basicId( d ) ] ];
        return row;
    },
    feature: function (mlco, d) {
        return mlco.genericPopText( d );
    },
    unknown: function (mlco, d) {
        return mlco.genericPopText( d );
    }
  }
};

loadMinerHash( standardMapLocMiners );
//registerMapLocLinker( '[NX][MR]_[0-9]+(\\.[0-9]+)?',
//                      "http://www.ncbi.nlm.nih.gov/nuccore/__ID__" );
registerMapLocLinker( '[NX][MR]_[0-9]+(\\.[0-9]+)?',
                      "mapLocReporter.pl?mode=rna&rna=__ID__" );
registerMapLocLinker( 'ENS[A-Z]*(T|P)[0-9]+(\\.[0-9]+)?',
                      "mapLocReporter.pl?mode=rna&rna=__ID__" );
registerMapLocLinker( 'CDD:\\d+',
                      "http://www.ncbi.nlm.nih.gov/Structure/cdd/cddsrv.cgi?uid=__NUM__" );
registerMapLocLinker( 'LOC[0-9]{1,}',
                      "http://www.ncbi.nlm.nih.gov/sites/entrez?db=gene&cmd=Retrieve&dopt=full_report&list_uids=__ID__" );
registerMapLocLinker( 'PMID:\\d+',
                      "http://www.ncbi.nlm.nih.gov/pubmed/?term=__NUM__" );

