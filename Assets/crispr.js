function hideshow(id){
	obj=document.getElementById(id)
	if (!obj) return

	if (obj.style.display=="block")
		obj.style.display="none"
	else
		obj.style.display="block"
}

function toggleImg(id) {
	var theImg = document.getElementById(id)
	if (!theImg) return
	var x=theImg.src.split("/")
	var t=x.length - 1
	var y=x[t]
	if (y=='plus.jpg')
		theImg.src="Assets/minus.jpg"
	else if (y=='minus.jpg')
		theImg.src="Assets/plus.jpg"
}

function showCharts( crispr_name, hdr_snp_flag ) {
    var sample=document.getElementById("select1").value;
	var high_res=document.getElementById("high_res").value;
	var plot_ext= high_res ? ".tif" : ".png";
    var str = "";
    if ( sample) {
        var types = ["cov", "ins", "del", "len"];
        str = "<table border=0>";
        for (i=0; i< types.length; i++) {
            if ( i%2 ==0 ) { str +="<tr>"; }
            str += "<td><img src=Assets/" + sample + "." + crispr_name + "." + types[i] + plot_ext + "></td>";
            if ( i%2 == 1 ) { str +="</tr>"; }
        }
        str += "</tr>";

        // chart for snp
        str += "<tr><td colspan=2><img src=Assets/" + sample + "." + crispr_name + ".snp" + plot_ext + "></td></tr>";

        //chart for hdr snp
        if ( hdr_snp_flag ) {
            str += "<tr><td colspan=2 align=center><img src=Assets/" + sample + "." + crispr_name + ".hdr.snp" + plot_ext + "></td></tr>";
        }

        str += "</table>";
    }
    document.getElementById("charts").innerHTML = str;
}

