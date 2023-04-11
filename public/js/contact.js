$(function() {
	var target = document.getElementById("send");
	var observer = new MutationObserver(records => {
		if( $("#mes").val().length <= 0 && !$("#checker").prop("checked") && !$("#send").prop("disabled")){
			$("#send").attr("disabled", "disabled");
		}
	});
	observer.observe(target, {
		attributes: true,
		attributeFilter: ['disabled']
	});
	$("#mes").bind("keyup change paste", function() {
		chck();
	});

	$("#checker").click(function() {
		chck();
	});
});

function chck(){
	var txt = $("#mes").val();
	var len = txt.length;
	if( len > 0 && $("#checker").prop("checked") ){
		$("#send").removeAttr("disabled");
	}
	else {
		$("#send").attr("disabled", "disabled");
	}
}

