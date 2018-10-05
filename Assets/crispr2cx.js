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

var sblock = 30;

function crisprPop (mlco, d) {
    var data = mlco.obj.data;
    var dd   = data[d];
    var tags = dd.tags || {};
    var st   = tags['Sequence Type'] || "";
    var text = new Array();
    text.push("<span class='pophead'>"+dd.name+"</span>");
    var mutlen = tags['Len'] || 0;
    if (st) {
        var typ = "<b>Class:</b> <span class='csp"+st+"'>&nbsp;"+
            st+"&nbsp;</span>";
        if (mutlen) typ += " "+mutlen+"bp";
        text.push(typ);
    }
    if (tags['Read Depth']) {
        var rd = "<b>Read Depth:</b> " + tags['Read Depth'];
        if (tags['Percent of Reads']) {
            rd += " = <span class='perc'>" + tags['Percent of Reads'] + "%</span>";
        }
        text.push(rd);
    }
    var samp = tags['Sample'];
    if (samp) {
        text.push("<b>Sample:</b> <a onclick=\"alert('Tell me where you want samples to link to')\" href='#'>"+samp+"</a>");
    }
    var sb = seqblock(dd);
    if (sb) {
        if (/\*/.test(sb)) {
            text.push("<span class='stop'>Stop Codon Present</span>");
        }
        if (mutlen % 3) {
            text.push("<span class='shift'>Frame Shift</span>");
        } else if (mutlen) {
            text.push("<span class='frame'>Frame Preserved</span>");
        }
        text.push("<b>Sequence:</b>"+sb);
        //if (st == 'Ins') text.push("<div class='smallnote'><b>NOTE:</b> The sequence above is accurate, but the display of insertions in the main window is not (they will incorrectly appear wild type)</div>");
    }
    //text.push( mlco.preDump(dd) );
    return text.join(mlco.cat);

    
    return mlco.genericPopText( d );
}

function protBracket( aa ) {
    if (!aa) return "";
    return "["+aa+"]";
}

function seqblock ( dd ) {
    var blk = dd.alnBlk;
    if (!blk) return "";
    return "<pre class='aln'>" + blk + "</pre>";
}

    
var crisprMiners = {
    mouseover: {
        crispr: crisprPop
    }
};

loadMinerHash( crisprMiners  );

