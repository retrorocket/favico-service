#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Mojolicious::Lite;
use Net::Twitter::Lite::WithAPIv1_1;
use File::Basename 'basename';
use File::Path;
use LWP::Simple 'mirror';
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON;
#use KCatch;
#use Data::Dumper;

use DBI;

$ENV{SCRIPT_NAME} = "/";

app->config(
    hypnotoad => {
        workers => 1
    },
);

my $database = app->home . '/favicotable.db';
my $data_source = "dbi:SQLite:dbname=$database";
my $data_hash = {
    AutoCommit => 0,
    PrintError => 0,
    RaiseError => 1,
    ShowErrorStatement => 1,
    AutoInactiveDestroy => 1
};

#$dbh = DBI->connect($data_source, undef, undef, $data_hash);
my $dbh;
#$dbh->{AutoCommit} = 0;

my $nt = Net::Twitter::Lite::WithAPIv1_1->new(
    consumer_key => "",
    consumer_secret => "",
    ssl => 1
#    legacy_lists_api => 0
);

my $nt_chrome = Net::Twitter::Lite::WithAPIv1_1->new(
    consumer_key => '',
    consumer_secret => '',
    ssl => 1
);

my $show_num = 20; #ページナビ表示数
my $Logined_name = "Home";
my $Login_name  = "Login";
my $Logout_name = "Logout";
my $Loging  =  0;

my $USERNAME_ERROR = "ユーザ名が不正です";
my $DB_ERROR = "DB接続エラーです";

sub page_count{ #ページナビカウンタ
    my ($statement) = @_;
    $statement->execute();
    my $row = $statement->fetch();
    my $count = int($row->[0]/$show_num);
    if($row->[0]%$show_num != 0 && $count > 0){
        $count++;
    }
    return $count;
}

sub name_check{ #ページナビカウンタ
    my ($name) = @_;
    if($name =~ /\W/ || $name eq "" || !defined($name)){
        return -1;
    }
    return 1;
}

sub page_check{
    my ($page) = @_;
    unless ($page =~ /\D/ || $page eq "" || !defined($page)) {
        $page  =  $page - 1;
        if($page < 0) {$page  = 0;}
    }
    else{
        $page  =  0;
    }
    return $page;
}

sub allfavs_check{
    my ($allfavs) = @_;
    if ($allfavs eq "on") {
        return "on";
    }
    return "off";
}

sub hst_check{
#    $dbh = DBI->connect($data_source, undef, undef, $data_hash);
    my ($sql, $flag) = @_;
    my $hst = $dbh->prepare($sql);
    unless($hst){
        my $errstr = $dbh->errstr;
        $dbh->disconnect;
        return -1;
    }

    my $ret = $hst->execute();
    unless($ret){
        my $errstr = $dbh->errstr;
        $hst->finish;
        undef $hst;
        $dbh->disconnect;
        return -1;
    }
    #$self->stash( timeline => $hst );
    my $scripts = [ ];
    if($flag == 2){
        while(my $ref = $hst->fetchrow_arrayref){
            my($aut, $kensu) = @$ref;
            push @{$scripts}, { aut => $aut, kensu => $kensu };
        }
    }
    elsif($flag == 3){
        while(my $ref = $hst->fetchrow_arrayref){
            my($file,$dat,$aut,$id) = @$ref;
            push @{$scripts}, { file => $file, dat => $dat, aut => $aut, id => $id };
        }
    }
    else {
        while(my $ref = $hst->fetchrow_arrayref){
            my($file,$dat,$aut) = @$ref;
            push @{$scripts}, { file => $file, dat => $dat, aut => $aut };
        }
    }
    
    $hst->finish;
    undef $hst;
    
    #付け足す
#    $dbh->disconnect;

    return $scripts;
}

app->defaults({'log' => 0, 'log_a_name' => '' });
############静的ルート#####################

under sub {

    my $self = shift;

    my $access_token = $self->session( 'access_token' );
    my $access_token_secret = $self->session( 'access_token_secret' );
    my $username = $self->session( 'screen_name' ) || '';

    my $logged = 0;
    if ($access_token && $access_token_secret){
        $logged = 1;
    }
    $self->stash('log' => $logged);
    $self->stash('log_a_name' => $username);
    return 1;
};

############ 拡張向けルート ##################
get '/page/auth_chrome' => sub {
    my $self = shift;

    my $cb_url = $self->url_for('chrome_auth_cb')->to_abs->scheme('https');
    my $url = $nt_chrome->
        get_authorization_url( callback => $cb_url );

    $self->session( token_chrome => $nt_chrome->request_token );
    $self->session( token_secret_chrome => $nt_chrome->request_token_secret );

    $self->redirect_to( $url );
    return;

} => 'chrome_auth';

get '/page/auth_chrome_cb' => sub {
    my $self = shift;
    my $verifier = $self->param('oauth_verifier') || '';
    my $token = $self->session('token_chrome') || '';
    my $token_secret = $self->session('token_secret_chrome') || '';

    $nt_chrome->request_token( $token );
    $nt_chrome->request_token_secret( $token_secret );

    # Access token取得
    my ($access_token, $access_token_secret, $user_id, $screen_name)
        = $nt_chrome->request_access_token( verifier => $verifier );

    $self->session( expires => 1 );

    $self->redirect_to( "https://.chromiumapp.org/callback?access_token_chrome="
    . $access_token
    . "&access_token_secret_chrome="
    . $access_token_secret);
    return;

} => 'chrome_auth_cb';

# Upload image file
post '/page/fav_oauth' => sub {
    my $filename;
    my $uri;
    my $filepath;
    my $self = shift;

    my $access_token = $self->param('access_token');
    my $access_token_secret = $self->param('access_token_secret');

    unless ($access_token && $access_token_secret){
        return  $self->render(json => {'result' =>"Twitterで認証を行なっていません"}); 
    }
    $nt_chrome->access_token( $access_token );
    $nt_chrome->access_token_secret( $access_token_secret );

    my $username = $nt_chrome->account_settings->{screen_name};

    $username= lc($username);
    my $top = $nt_chrome->show_user({screen_name=>${username}});
    my $a_username = $top->{screen_name};

    my $favname = $self->param('favname');
    if(&name_check($favname)<0){
        return  $self->render(json => {'result' => "ユーザ名が不正です"}); 
    }
    $favname= lc($favname);
    eval{
        $top = $nt_chrome->show_user({screen_name=>${favname}});
    };
    if($@){
        return  $self->render(json => {'result' =>"エラーが発生しました（". $@ ."）"}); 
    }
    my $a_favname = $top->{screen_name};

    # Image base URL
    my $IMAGE_BASE = app->home .'/public/image/'.$username;
    my $IMAGE_DIR  = $IMAGE_BASE;

    # Create directory if not exists
    unless (-d $IMAGE_DIR) {
        mkpath $IMAGE_DIR or die "Cannot create dirctory: $IMAGE_DIR";
    }

    eval{
        $uri = $top->{profile_image_url};
        $filename = $favname."_".basename($uri);
        $filepath = $IMAGE_DIR."/".$filename;

        # あらかじめ「MuneKyun」フォルダを作っておく
    };
    if($@){
        return  $self->render(json => {'result' =>"エラーが発生しました（". $@ ."）"}); 
    }

    if(-f $filepath){
        return  $self->render(json => {'result' =>"このアイコン画像はすでにお気に入りに登録しています"}); 
    }
    else{
        mirror($uri, $filepath);
    }
    unless(-f $filepath){
        return  $self->render(json => {'result' =>"アイコンが取得できませんでした．再度登録し直すかユーザー名を確認してください"}); 
    }

    my ($sec, $min, $hour, $mday, $month, $year) = localtime;
    $month = $month + 1;
    $year = $year + 1900;

    my $name = sprintf("%04s/%02s/%02s %02s:%02s:%02s",
        $year, $month, $mday, $hour, $min, $sec);

    $dbh = DBI->connect($data_source, undef, undef, $data_hash);

    eval{
        my $insert = "insert into books (user_name, file_name, date, author) values ('${a_username}', '${filename}', '${name}', '${a_favname}');";
        $dbh->do($insert);
        $dbh->commit;
        $dbh->disconnect;
    };
    if($@){
        $dbh->rollback;
        $dbh->disconnect;
        return  $self->render(json => {'result' =>"エラーが発生しました（". $@ ."）"}); 
    }
    return  $self->render(json => {'result' =>"${a_favname}さんのアイコンをお気に入りに登録しました"}); 

} => 'fav_oauth';
###############拡張向けルート終わり####################

# Upload image file
post '/fav' => sub {
    my $filename;
    my $uri;
    my $filepath;
    my $self = shift;

    my $access_token = $self->session( 'access_token' ) || '';
    my $access_token_secret = $self->session( 'access_token_secret' ) || '';
    my $username = $self->session( 'screen_name' ) || '';

    unless ($access_token && $access_token_secret){
        return $self->render(
            template => 'error',
            message  => "セッションタイムアウトしました．"
        );
    }
    $nt->access_token( $access_token );
    $nt->access_token_secret( $access_token_secret );

    $username= lc($username);
    my $top = $nt->show_user({screen_name=>${username}});
    my $a_username = $top->{screen_name};

    my $favname = $self->param('favname');
    if(&name_check($favname)<0){
            return $self->render(
            template => 'error',
            message  => $USERNAME_ERROR
        );
    }

    $favname= lc($favname);
    $top = $nt->show_user({screen_name=>${favname}});
    my $a_favname = $top->{screen_name};

    # Image base URL
    my $IMAGE_BASE = app->home .'/public/image/'.$username;
    my $IMAGE_DIR  = $IMAGE_BASE;

    # Create directory if not exists
    unless (-d $IMAGE_DIR) {
        mkpath $IMAGE_DIR or die "Cannot create dirctory: $IMAGE_DIR";
    }

    eval{
        $uri = $top->{profile_image_url};
        $filename = $favname."_".basename($uri);
        $filepath = $IMAGE_DIR."/".$filename;
    };
    if($@){
        return $self->render(
            template => 'error',
            message  => "エラーが発生しました（". $@ ."）"
        );
    }

    if(-f $filepath){
        return $self->render(
            template => 'error',
            message  => "このアイコン画像はすでにお気に入りに登録しています"
        );
    }
    else{
        mirror($uri, $filepath);
    }
    unless(-f $filepath){
            return $self->render(
            template => 'error',
            message  => "アイコンが取得できませんでした．再度登録し直すかユーザー名を確認してください"
        );
    }

    my ($sec, $min, $hour, $mday, $month, $year) = localtime;
    $month = $month + 1;
    $year = $year + 1900;

    my $name = sprintf("%04s/%02s/%02s %02s:%02s:%02s",
        $year, $month, $mday, $hour, $min, $sec);
    $dbh = DBI->connect($data_source, undef, undef, $data_hash);
    eval{
        my $insert = "insert into books (user_name, file_name, date, author) values ('${a_username}', '${filename}', '${name}', '${a_favname}');";
        $dbh->do($insert);
        $dbh->commit;
        $dbh->disconnect;
    };
    if($@){
        $dbh->rollback;
        $dbh->disconnect;

        return $self->render(
            template => 'error',
            message  => "エラーが発生しました（". $@ ."）"
        );
    }
#付け足す
#$dbh->disconnect;
    $self->redirect_to( 'index' );

} => 'fav';

get '/page/auth' => sub {
    my $self = shift;

    my $cb_url = $self->url_for('auth_cb')->to_abs->scheme('https');
    my $url = $nt->
    get_authorization_url( callback => $cb_url );

    $self->session( token => $nt->request_token );
    $self->session( token_secret => $nt->request_token_secret );

    $self->redirect_to( $url );
    return;

} => 'auth';

get '/page/auth_cb' => sub {
    my $self = shift;
    my $verifier = $self->param('oauth_verifier') || '';
    my $token = $self->session('token') || '';
    my $token_secret = $self->session('token_secret') || '';

    $nt->request_token( $token );
    $nt->request_token_secret( $token_secret );

    # Access token取得
    my ($access_token, $access_token_secret, $user_id, $screen_name)
    = $nt->request_access_token( verifier => $verifier );

    # Sessionに格納
    $self->session( access_token => $access_token );
    $self->session( access_token_secret => $access_token_secret );
    $self->session( screen_name => $screen_name );

    $self->redirect_to('index');
    return;

} => 'auth_cb';

get '/bye/logout' => sub {
    my $self = shift;
    $self->session( expires => 1 );
    $self->stash('log' => 0 );
    $self->stash('log_a_name' => '' );
} => 'logout';

get '/page/check' => sub {

    my $self = shift;
    my $r_val = "error";

    my $access_token = $self->session( 'access_token' ) || '';
    my $access_token_secret = $self->session( 'access_token_secret' ) || '';

    unless ($access_token && $access_token_secret){
        return $self->render(json => {'filename' => $r_val});
    }
    $nt->access_token( $access_token );
    $nt->access_token_secret( $access_token_secret );

    my $username = $self->param('username');

    if($username =~ /\W/){
        return $self->render(json => {'filename' => $r_val});
    }

    eval{
        my $top = $nt->show_user({screen_name=>${username}});
        $r_val = $top->{profile_image_url};
    };
    if($@){
        $r_val = "error";
    }

    return $self->render(json => {'filename' => $r_val});

} => 'check';

post '/delete' => sub {
    my $self = shift;
    my $access_token = $self->session( 'access_token' ) || '';
    my $access_token_secret = $self->session( 'access_token_secret' ) || '';
    my $username = $self->session( 'screen_name' ) || '';

    unless ($access_token && $access_token_secret){
        $dbh->disconnect;
        return $self->render(json => {'result' => "error"});
    }

    #my $r_val = "error";
    my $filename = $self->param('filename');
    my $iconid = $self->param('iconid');
    my $author = $self->param('author');
    if($author =~ /\W/ || $iconid =~ /\D/ || $filename =~ /\'/ || $filename =~ /\;/){
        return $self->render(json => {'result' => "error"});
    }

    $username= lc($username);

    $dbh = DBI->connect($data_source, undef, undef, $data_hash);

    my $sql = "delete from books where author = '${author}' and id = ${iconid} and file_name='${filename}' and LOWER(user_name)=LOWER('${username}');";

    my $ret = $dbh->do($sql);

    unless($ret){
        $dbh->rollback;
        $dbh->disconnect;
        return $self->render(json => {'result' => "error"});
    }

    my $IMAGE_BASE = app->home .'/public/image/'.$username;
    my $IMAGE_DIR  = $IMAGE_BASE;

    if(unlink ( $IMAGE_DIR."/".$filename )){
        $dbh->commit;
        $dbh->disconnect;
    }
    else {
        $dbh->rollback;
        $dbh->disconnect;
        return $self->render(json => {'result' => "error"});
    }
    $self->render(json => {'result' => "complete"});

} => 'delete';

post '/all_delete' => sub {
    my $self = shift;
    my $access_token = $self->session( 'access_token' ) || '';
    my $access_token_secret = $self->session( 'access_token_secret' ) || '';
    my $username = $self->session( 'screen_name' ) || '';

    unless ($access_token && $access_token_secret){
        $dbh->disconnect;
        return $self->render(
            template => 'error',
            message  => 'セッションがタイムアウトしました'
        );
    }

    $username= lc($username);
    $dbh = DBI->connect($data_source, undef, undef, $data_hash);
    my $sql = "delete from books where LOWER(user_name)=LOWER('${username}');";

    my $ret = $dbh->do($sql);

    unless($ret){
        $dbh->rollback;
        $dbh->disconnect;
        return $self->render(
            template => 'error',
            message  => $DB_ERROR
        );
    }

    my $IMAGE_BASE = app->home .'/public/image/'.$username;
    my $IMAGE_DIR  = $IMAGE_BASE;

    if(rmtree($IMAGE_DIR)){
        $dbh->commit;
        $dbh->disconnect;
        $self->session( expires => 1 );
        return $self->render(
            template => 'thx'
        );
    }
    else{
        $dbh->rollback;
        $dbh->disconnect;
        return $self->render(
            template => 'error',
            message  => 'ファイル削除エラーです'
        );
    }

} => 'all_delete';

get '/page/about'  => sub {
    my $self = shift;
    return $self->render(
        template => 'default'
    );
}  => 'about';

get '/page/contact'  => sub {
    my $self = shift;
    return $self->render(
        template => 'contact'
    );
}  => 'contact';

post '/page/contact/send'  => sub {
    my $self = shift;
    my $sender_name = $self->param('name') || '';
    my $sender_contact = $self->param('contact') || '';
    my $sender_message = $self->param('message');
    my $sender_checker = $self->param('checker');
    my $sender_recaptcha_response = $self->param('g-recaptcha-response');

    if(!defined($sender_checker) || $sender_checker ne "checked" || !defined($sender_message) || $sender_message eq "" ){
        return $self->render(
            message  => "必須項目を入力してください"
        );
    }

    my $params = [
        secret => '',
        response => $sender_recaptcha_response,
    ];
    #my $log = app->log;
    my $ua = new LWP::UserAgent;
    my $res = $ua->request( POST('https://www.google.com/recaptcha/api/siteverify', $params) );
    #$log->error("test");
    if ($res->is_success) {
        my $result = decode_json($res->content);
        if(!$result->{"success"}) {
            return $self->render(
                message  => "reCAPTCHAによる認証に失敗しました"
            );
        }
    } else {
        return $self->render(
            message  => "reCAPTCHAによる認証に失敗しました"
        );
    }

    plugin 'mail';

    $self->mail(
        from => 'favico at mail.retrorocket.biz',
        type => 'text/plain',
        to      => 'mail at retrorocket.biz',
        subject => 'favico!問い合わせ',
        data    => "お名前：".$sender_name."\n"."連絡先：".$sender_contact."\n"."内容：".$sender_message."\n"
    );

    $self->stash('message' => "メッセージが送信されました");

} => 'contact_sender';

get '/page/tos' => sub {
    my $self = shift;
    unless($self->param('username')){
        return $self->redirect_to( 'index' );
    }
    return $self->redirect_to( 'user', username => $self->param('username') );
}  => 'user_old';


#########動的ルート#############


group {

    under '/'  => sub {

    my $self = shift;

    my $mode = $self->param('mode') || '';
    my $access_token = $self->session( 'access_token' );
    my $access_token_secret = $self->session( 'access_token_secret' );
    my $username = $self->session( 'screen_name' );

    if(( !$access_token || !$access_token_secret ) && $mode ne "login" ){
        $self->render(
            template => 'default'
        );
        return;
    }

    # セッションにaccess_tokenが残ってなければ再認証
    unless ($access_token && $access_token_secret){
        $self->redirect_to( 'auth' );
        return;
    }

    $nt->access_token( $access_token );
    $nt->access_token_secret( $access_token_secret );

    #名前管理
    $username= lc($username);
    my $top = $nt->show_user({screen_name=>${username}});
    my $a_username = $top->{screen_name};
    $self->stash('name' => $username);
    $self->stash('a_name' => $a_username);


    #左メニューフラグ管理
    my $allfavs = $self->param('allfavs') || '';
    $allfavs = &allfavs_check($allfavs);
    $self->stash( 'allfavs' => $allfavs );


    #ページ数管理
    my $page = $self->param('page') || '';
    $page  = &page_check($page);
    $self->stash('paging' => $page+1);
    my $spage  =  $page * $show_num;
    $self->stash('spage' => $spage);

    $dbh = DBI->connect($data_source, undef, undef, $data_hash);

    #左メニュー用ユーザー管理
    my $sql2 = "SELECT author, COUNT(id) AS kensu FROM books WHERE LOWER(user_name)=LOWER('${username}') GROUP BY author ORDER BY kensu DESC LIMIT 10";
    if($allfavs eq "on"){
        $sql2 = "SELECT author, COUNT(id) AS kensu FROM books WHERE LOWER(user_name)=LOWER('${username}') GROUP BY author ORDER BY kensu DESC";
    }
    my $h2 = &hst_check($sql2, 2);
    if($h2 == -1){
        $dbh->disconnect;
        $self->render(
            template => 'error',
            message  => $DB_ERROR
        );
        return;
    }
    $self->stash( usertimeline => $h2 );

    $self->stash('pos' => '');

    #付け足す
    $dbh->disconnect;

    return 1;
};

get '/' => sub{

    my $self = shift;
    my $stash = $self->stash;
    my $username = $stash->{'name'};
    my $spage =  $stash->{'spage'};

    $dbh = DBI->connect($data_source, undef, undef, $data_hash);

    #タイムライン管理
    my $sql = "SELECT file_name,date,author,id FROM books WHERE LOWER(user_name)=LOWER('${username}') ORDER BY id DESC LIMIT ${spage}, ${show_num}";
    my $h = &hst_check($sql, 3);
    if($h == -1){
        $dbh->disconnect;
        return $self->render(
            template => 'error',
            message  => $DB_ERROR
        );
    }
    $self->stash( timeline => $h );


    #カウント管理
    $dbh = DBI->connect($data_source, undef, undef, $data_hash);
    my $statement = $dbh->prepare("SELECT COUNT(id) FROM books WHERE LOWER(user_name)=LOWER('${username}')");
    my $count = &page_count($statement);
    $self->stash('count' => $count);

    $statement->finish;
    undef $statement;
    $dbh->disconnect;

    return $self->render;

} => 'index';

get '/u/:fav' => sub{

    my $self = shift;
    my $stash = $self->stash;
    my $username = $stash->{'name'};
    my $spage =  $stash->{'spage'};


    #fav定義時のタイムライン
    my $fav = $self->param('fav');
    if ( &name_check($fav) < 0){
        return $self->render(
            template => 'error',
            message  => $USERNAME_ERROR
        );
    }
    else{
        $fav= lc($fav);
    }

    $dbh = DBI->connect($data_source, undef, undef, $data_hash);

    #タイムライン取得：エラー発生時-1
    my $sql = "SELECT file_name,date,author,id FROM books WHERE LOWER(user_name)=LOWER('${username}') AND LOWER(author)=LOWER('${fav}') ORDER BY id DESC LIMIT ${spage}, ${show_num}";
    my $h = &hst_check($sql, 3);
    if($h == -1){

        $dbh->disconnect;
        return $self->render(
            template => 'error',
            message  => $DB_ERROR
        );
    }
    $self->stash( timeline => $h );

    $dbh = DBI->connect($data_source, undef, undef, $data_hash);
    #ページ数管理
    my $statement = $dbh->prepare("SELECT COUNT(id) FROM books WHERE LOWER(user_name)=LOWER('${username}') AND LOWER(author)=LOWER('${fav}')");
    my $count = &page_count($statement);
    $self->stash('count' => $count);


    #左メニューポジション
    $self->stash('pos' => $self->param('fav'));

    $statement->finish;
    undef $statement;
    $dbh->disconnect;

    return $self->render(
        template => 'index'
    );

} =>'index_favname';

};


group {
    under '/:username' => sub {

    my $self = shift;

    my $access_token = $self->session( 'access_token' ) || '';
    my $access_token_secret = $self->session( 'access_token_secret' ) || '';
    my $logged_name = $self->session( 'screen_name' ) || '';
    my $profile_url = "";

    #ページチェック
    my $page = $self->param('page') || '';
    $page  = &page_check($page);
    $self->stash('paging' => $page+1);
    my $spage  =  $page * $show_num;
    $self->stash('spage' => $spage);


    #全ユーザー表示チェック
    my $allfavs = $self->param('allfavs') || '';
    $allfavs = &allfavs_check($allfavs);
    $self->stash( 'allfavs' => $allfavs );


    #対象ユーザー名チェック
    my $username = $self->param('username');
    if (&name_check($username) < 0){
        $self->render(
            template => 'error',
            message  => $USERNAME_ERROR
        );
        return;
    }
    $username= lc($username);
    $self->stash('name' => $username);

    $dbh = DBI->connect($data_source, undef, undef, $data_hash);
    #ユーザー名真名チェック
    my $sql_user = "SELECT user_name FROM books WHERE LOWER(user_name)=LOWER('${username}') LIMIT 1";
    my $a_username="";
    my $result = $dbh->selectrow_array($sql_user) || '';
    #$dbh->disconnect;
    if ($result ne "") {
        $a_username = $result;
    }
    $self->stash('a_name' => $a_username);
    #$dbh->disconnect;

    #サイドフレーム用ユーザー表示処理
    my $sql2 = "SELECT author, COUNT(id) AS kensu FROM books WHERE LOWER(user_name)=LOWER('${username}') GROUP BY author ORDER BY kensu DESC LIMIT 10";
    if($allfavs eq "on"){
        $sql2 = "SELECT author, COUNT(id) AS kensu FROM books WHERE LOWER(user_name)=LOWER('${username}') GROUP BY author ORDER BY kensu DESC";
    }

    my $h = &hst_check($sql2, 2);
    if($h == -1){
        $dbh->disconnect;
        $self->render(
            template => 'error',
            message  => $DB_ERROR
        );
        return;
    }
    $self->stash( usertimeline => $h );


    #デフォルトのfav名は空
    $self->stash('pos' => '');

    #付け足す
    $dbh->disconnect;

    return 1;

};


get '/' => sub{

    my $self = shift;
    my $stash = $self->stash;
    my $username = $stash->{'name'};
    my $spage =  $stash->{'spage'};

    #タイムライン
    #&hst_check($username,$spage);
    $dbh = DBI->connect($data_source, undef, undef, $data_hash);
    #タイムライン取得：エラー発生時-1
    my $sql = "SELECT file_name,date,author FROM books WHERE LOWER(user_name)=LOWER('${username}') ORDER BY id DESC LIMIT ${spage}, ${show_num}";
    my $h = &hst_check($sql, 1);
    if($h == -1){
        return $self->render(
            template => 'error',
            message  => $DB_ERROR
        );
    }
    $self->stash( timeline => $h );

    #ページ数
    my $statement = $dbh->prepare("SELECT COUNT(id) FROM books WHERE LOWER(user_name)=LOWER('${username}')");
    my $count = &page_count($statement);
    $self->stash('count' => $count);

    $statement->finish;
    undef $statement;
    $dbh->disconnect;

    $self->render;

} => 'user';


get '/u/:fav' => sub{

    my $self = shift;
    my $stash = $self->stash;
    my $username = $stash->{'name'};
    my $spage =  $stash->{'spage'};


    #fav定義時のタイムライン
    my $fav = $self->param('fav');
    if ( &name_check($fav) < 0){
        return $self->render(
            template => 'error',
            message  => $USERNAME_ERROR
        );
    }
    else{
        $fav= lc($fav);
    }
    $dbh = DBI->connect($data_source, undef, undef, $data_hash);
    #タイムライン取得：エラー発生時-1
    my $sql = "SELECT file_name,date,author FROM books WHERE LOWER(user_name)=LOWER('${username}') AND LOWER(author)=LOWER('${fav}') ORDER BY id DESC LIMIT ${spage}, ${show_num}";

    my $h = &hst_check($sql, 1);
    if($h == -1){
        $dbh->disconnect;
        return $self->render(
            template => 'error',
            message  => $DB_ERROR
        );
    }
    $self->stash( timeline => $h );


    #ページ数管理
    my $statement = $dbh->prepare("SELECT COUNT(id) FROM books WHERE LOWER(user_name)=LOWER('${username}') AND LOWER(author)=LOWER('${fav}')");
    my $count = &page_count($statement);
    $self->stash('count' => $count);


    #左メニューポジション
    $self->stash('pos' => $self->param('fav'));

    $statement->finish;
    undef $statement;
    $dbh->disconnect;

    $self->render(
        template => 'user'
    );

} => 'user_favname';

};

app->sessions->secure(1);
app->sessions->cookie_name( "favico" );
app->secrets([""]); # セッション管理のために付けておく
app->start;

