$(function() {

	$(".delete").hide();
	$(".favtweet").hide();

	$(".favtweet").click(function(){
		var url = $(this).attr("href");
		window.open(url,'tweet','width=500,height=300');
		return false;
	});

	$("#chck").click(function(){
		$("#chck_img").attr("src", "//favico.retrorocket.biz/img/ajax-loader.gif");
		var favname = $("#fname").val();
		$.get("//favico.retrorocket.biz/page/check", { username: favname },
  			function(data){
				if(data.filename != "error"){
					$("#chck_img").attr("src", data.filename);
				}
				else{
					$("#chck_img").attr("src", "//favico.retrorocket.biz/img/error.png");
				}
		});

	});

	$("#chck2").click(function(){
		$("#chck_img2").attr("src", "//favico.retrorocket.biz/img/ajax-loader.gif");
		var favname = $("#fname2").val();
		$.get("//favico.retrorocket.biz/page/check", { username: favname },
  			function(data){
				if(data.filename != "error"){
					$("#chck_img2").attr("src", data.filename.replace("normal","mini"));
				}
				else{
					$("#chck_img2").attr("src", "//favico.retrorocket.biz/img/error2.png");
				}
		});
		return false;
	});

	$(".hov").mouseover(function(){
		//$(".favcon").show();
		$(this).find(".delete").show();
		$(this).find(".favtweet").show();

	});
	$(".hov").mouseleave(function(){
		$(this).find(".delete").hide();
		$(this).find(".favtweet").hide();
	});

	$(".delete").mouseover(function(){
		//$(".favcon").show();
		$(this).find("i").attr("class","icon-star-empty");
	});
	$(".delete").mouseleave(function(){
		$(this).find("i").attr("class","icon-star");
	});

	$(".delete").click(function(){
		var myRet = confirm("このアイコンをお気に入りから解除しますか？");
  		if (!myRet) {
			return false;
		}

		var filename = $(this).attr("filename");
		var author = $(this).attr("author");
		var iconid = $(this).attr("iconid");

		$.post(
			"//favico.retrorocket.biz/delete",
			{ filename: filename, author: author, iconid: iconid },
  			function(data){
				if(data.result != "error"){
					alert("解除しました");
					location.reload();
				}
				else{
					alert("解除できませんでした");
				}
			});
	});

	/*$("#all_delete").submit(function() {
		var myRet = confirm("ユーザ情報を全消去します");
  		if (!myRet) {
			return false;
		}
		return true;
	});*/

	$("#a_all_delete").click(function() {
		var myRet = confirm("ユーザ情報を全消去します");
		if (!myRet) {
			return false;
		}
		$("#all_delete").submit();
	});

});
