$(function() {

	$(".navbar-search").submit(function(){
		if($("#sq").val().match(/\W/) || $("#sq").val().length  ==  0){
			alert("ユーザー名が不正です");
			return false;
		}
		location.href = "//favico.retrorocket.biz/" + $("#sq").val();
		return false;
	});

});

