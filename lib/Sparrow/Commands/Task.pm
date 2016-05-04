package Sparrow::Commands::Task;

use strict;

use base 'Exporter';

use Sparrow::Constants;
use Sparrow::Misc;
use Sparrow::Commands::Plugin;

use Carp;
use File::Basename;
use File::Path;

use JSON;
use Data::Dumper;
use File::Copy;

our @EXPORT = qw{

    task_add
    task_show
    task_remove

    task_ini
    task_load_ini

    task_run

    task_get
    task_set

};

sub task_add {

    my $project = shift or confess "usage: task_add(*project,task,plugin)";
    my $tid     = shift or confess "usage: task_add(project,*task,plugin)";
    my $pid     = shift or confess "usage: task_add(project,task,*plugin)";

    confess "unknown project" unless  -d sparrow_root."/projects/$project";

    if  (-d sparrow_root."/projects/$project/tasks/$tid"){
      print "task $project/$tid already exists - nothing to do here\n\n";
      exit(0);
    }

    $project=~/^[\w\d-\._]+$/ or confess 'project parameter does not meet naming requirements - /^[\w\d-\._]+$/';
    $tid=~/^[\w\d-\._]+$/ or confess 'task parameter does not meet naming requirements - /^[\w\d-\._]+$/';

    mkdir sparrow_root."/projects/$project/tasks/$tid" or confess "can't create task directory: $!";

    my $ptype;

    if ($pid=~/(public|private)@/){
        $ptype = $1;
        $pid=~s/(public|private)@//;
    }
    
    if (! $ptype and -f sparrow_root."/plugins/public/$pid/sparrow.json" and -d sparrow_root."/plugins/private/$pid" ){
        warn "both public and private $pid plugin exists; choose `public\@$pid` or `private\@$pid` to overcome this ambiguity";
        return;
    }elsif( -f sparrow_root."/plugins/public/$pid/sparrow.json"  and $ptype ne 'private' ){
        task_set($project,$tid,'plugin',"public\@$pid");
        print "task - set plugin to public\@$pid\n\n";
    }elsif( -d sparrow_root."/plugins/private/$pid/" and $ptype ne 'public'  ){
        task_set($project,$tid,'plugin',"private\@$pid");
        print "task - set plugin to private\@$pid\n\n";
    }else{
        confess "plugin is not installed, you need to install it first to use in task";
    }    

    print "task $project/$tid successfully created\n\n";

}

sub task_show {

    my $project  = shift or confess "usage: task_show(*project,task)";
    my $tid      = shift or confess "usage: task_show(project,*task)";

    confess "unknown project" unless  -d sparrow_root."/projects/$project";
    confess "unknown task" unless  -d sparrow_root."/projects/$project/tasks/$tid";


    print "[task $project/$tid]\n\n";

    local $Data::Dumper::Terse=1;
    print Dumper(task_get($project,$tid)), "\n\n";    

    my $ini_file = sparrow_root."/projects/$project/tasks/$tid/suite.ini";

    if (-f $ini_file){
       print "[test suite ini file - $ini_file]\n\n";
        open F, $ini_file or confess "can't open $ini_file to read: $!";
        print join "", <F>;
        close F;
    }else{
       print "test suite ini file: not found\n"
    }


}

sub task_remove {

    my $project = shift or confess('usage: task_remove(*project,task)');
    my $tid     = shift or confess('usage: task_remove(project,*task)');

    $project=~/^[\w\d-\._]+$/ or confess 'project parameter does not meet naming requirements - /^[\w\d-\._]+$/';
    $tid=~/^[\w\d-\._]+$/ or confess 'task parameter does not meet naming requirements - /^[\w\d-\._]+$/';

    if (-d sparrow_root."/projects/$project" and -d sparrow_root."/projects/$project/tasks/$tid" ){
        rmtree( sparrow_root."/projects/$project/tasks/$tid" );
        print "task $project/$tid successfully removed\n\n";
    }else{
        warn "unknown task";
    }

}

sub task_ini {

    my $project  = shift or confess "usage: task_ini(*project,task)";
    my $tid      = shift or confess "usage: task_ini(project,*task)";

    confess "unknown project" unless  -d sparrow_root."/projects/$project";
    confess "unknown task" unless  -d sparrow_root."/projects/$project/tasks/$tid";
    confess "please setup your preferable editor via EDITOR environment variable\n" unless editor;

    exec editor.' '.sparrow_root."/projects/$project/tasks/$tid/suite.ini";

}

sub task_load_ini {

    my $project         = shift or confess "usage: task_load_ini(*project,task,path)";
    my $tid             = shift or confess "usage: task_load_ini(project,*task,path)";
    my $ini_file_path   = shift or confess "usage: task_load_ini(project,*task,path)";

    confess "unknown project" unless  -d sparrow_root."/projects/$project";
    confess "unknown task" unless  -d sparrow_root."/projects/$project/tasks/$tid";

    my $dest_path = sparrow_root."/projects/$project/tasks/$tid/suite.ini";
    copy($ini_file_path,$dest_path) or confess "Copy failed: $!";

    print "loaded test suite ini from $ini_file_path OK \n\n";

}


sub task_run {

    my $project  = shift or confess "usage: task_run(*project,task,options)";
    my $tid      = shift or confess "usage: task_run(project,*task,options)";
    my $options  = join ' ', @ARGV;

    confess "unknown project" unless  -d sparrow_root."/projects/$project";
    confess "unknown task" unless  -d sparrow_root."/projects/$project/tasks/$tid";

    my $task_set = task_get($project,$tid);

    confess "plugin not set" unless $task_set->{'plugin'};

    my $pdir = sparrow_root."/plugins/".($task_set->{'install_dir'});

    confess 'plugin not installed' unless -d $pdir;

    my $spj = plugin_meta($pdir);
    my $cmd;
    
    if ($spj->{engine} and $spj->{engine} eq 'generic'){
        $cmd = 'cd '.$pdir.' && '."carton exec 'strun --root ./ ";
        if ($options=~/--yaml\s+(\S+)/){
          my $path = $1;
          $cmd.=" --yaml $path";
        }else{
          my $path = sparrow_root."/projects/$project/tasks/$tid/suite.ini";
          $cmd.=" --ini $path" if -f $path;
        }
        $cmd.=" --host $task_set->{base_url}" if $task_set->{'base_url'};
    }else{
        $cmd = 'cd '.$pdir.' && '."carton exec 'swat ./ ";
        $cmd.=" $task_set->{base_url}";
        if ($options=~/--yaml\s+(\S+)/){
          my $path = $1;
          $cmd.=" --yaml $path";
        }else{
          my $path = sparrow_root."/projects/$project/tasks/$tid/suite.ini";
          $cmd.=" --ini $path" if -f $path;
        }
    }

    if ($options=~s/--cron//) {
        $cmd.=" $options'";
        my $repo_file = sparrow_root.'/reports/report-'.$project.'-'.$tid.'-'.$$.'.txt';
        exec "( $cmd 1>$repo_file 2>\&1 && rm $repo_file  )  || ( cat $repo_file ; rm -v $repo_file; exit 1; )";
    } else {
        $cmd.=" $options'";
        print "# $cmd\n\n";
        exec $cmd;
    }

}


sub task_get {

    my $project = shift or confess "usage: task_get(*project,task)";
    my $tid     = shift or confess "usage: task_get(project,*task)";

    my $data;
    
    if (open F, sparrow_root."/projects/$project/tasks/$tid/settings.json") { 
        my $str = join "", <F>;
        close F;
        $data = decode_json($str);
        if ($data->{plugin}) {
            my ($t,$name) = split '@' , $data->{plugin};
            $data->{install_dir} =  "$t/$name";
            $data->{type} = $t;
        }
    } else {
        $data = {};
    }
    return $data;

}

sub task_set {

    my $project  = shift or confess "usage: task_set(*project,task,args)";
    my $tid      = shift or confess "usage: task_set(project,*task,args)";
    my %args     = @_;

    my $task_settings = task_get($project,$tid); 

    open F, ">", sparrow_root."/projects/$project/tasks/$tid/settings.json" or 
        confess "can't open file to write: projects/$project/tasks/$tid/settings.json";

    for my $f (keys %args){
        $task_settings->{$f} = $args{$f};
    }

    print F encode_json($task_settings);
    close F;

}


1;
