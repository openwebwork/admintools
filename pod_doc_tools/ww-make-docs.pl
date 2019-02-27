#!/usr/bin/perl

use strict;
use warnings;
use 5.10.0;

package WeBWorK::Utils::HTMLDocs;

use File::Find;
use File::Temp qw(tempfile);
use IO::File;
use Pod::Find qw(pod_find simplify_name contains_pod);
use Pod::Html;
#use Pod::PP;
use POSIX qw(strftime);
use Data::Dumper;

our @sections = (
	'/' => "(root)",
	bin => "Scripts",
	conf => "Config Files",
	doc => "Documentation",
	lib => "Libraries",
	macros => "Macros",
    clients => "Clients",
    t       => "test modules",
    htdocs  => "web accessible docs",
);

sub new {
	my ($invocant, %o) = @_;
	my $class = ref $invocant || $invocant;
	
	my @section_list = exists $o{sections} ? @{$o{sections}} : @sections;
	my $section_hash = {@section_list};
	my $section_order = [ map { $section_list[2*$_] } 0..$#section_list/2 ];
	delete $o{sections};
	
	my $self = {
		%o,
		idx => {},
		section_hash => $section_hash,
		section_order => $section_order,
	};
	return bless $self, $class;
}

sub convert_pods {
	my $self = shift;
	my $source_root = $self->{source_root};
	my $dest_root = $self->{dest_root};
	my $subdirs = do {
		my $dh;
		opendir $dh, $source_root;
		join ':',
			grep { not (/^\./ or /^(CVS|.svn)$/) and -d "$source_root/$_" }
				readdir $dh;
	};
	$self->{subdirs} = $subdirs;
	
	find({wanted => $self->gen_pod_wanted, no_chdir => 1}, $source_root);
	$self->write_index("$dest_root/index.html");
}

sub gen_pod_wanted {
	my $self = shift;
	return sub {
		my $path = $File::Find::name;
		my $dir = $File::Find::dir;
		my ($name) = $path =~ m|^$dir(?:/(.*))?$|;
		$name = '' unless defined $name;
		
		if ($name =~ /^\./) {
			$File::Find::prune = 1;
			return;
		}
		unless (-f $path or -d $path) {
			$File::Find::prune = 1;
			return;
		}
		if (-d _ and $name =~ /^(CVS|RCS|.svn)$/) {
			$File::Find::prune = 1;
			return;
		}
		
		return if -d _;
		return unless contains_pod($path);
		$self->process_pod($path);
	};
}

sub process_pod {
	my ($self, $pod_path) = @_;
	my $source_root = $self->{source_root};
	my $dest_root = $self->{dest_root};
	my $dest_url = $self->{dest_url};
	my $subdirs = $self->{subdirs};
	
	my $pod_name;
	
	my ($subdir, $filename) = $pod_path =~ m|^$source_root/(?:(.*)/)?(.*)$|;
	my ($subdir_first, $subdir_rest)=('','');
	say "subdir $subdir";
	if (defined $subdir) {
		if ($subdir =~ m|/|) {
			($subdir_first, $subdir_rest) = $subdir =~ m|^([^/]*)/(.*)|;
		} else {
			$subdir_first = $subdir;
		}
	}
	say "subdir_first: ", $subdir_first//'';
	say "subdir_rest: ",  $subdir_rest//'';
	say '';

	$pod_name = (defined $subdir_rest ? "$subdir_rest/" : "") . $filename;
	if ($filename =~ /\.(plx?|pg)$/ or $filename !~ /\./) {
		$filename .= '.html';
	} elsif ($filename =~ /\.pod$/) {
		$pod_name =~ s/\.pod$//;
		$filename =~ s/\.pod$/.html/;
	} elsif ($filename =~ /\.pm$/) {
		$pod_name =~ s/\.pm$//;
		$pod_name =~ s|/+|::|g;
		$filename =~ s/\.pm$/.html/;
	}
	my $html_dir = defined $subdir ? "$dest_root/$subdir" : $dest_root;
	my $html_path = "$html_dir/$filename";
	my $html_rel_path = defined $subdir ? "$subdir/$filename" : $filename;
	
	# deal with potential failure
	if (not defined $subdir) {
		my $source_root_last = $source_root;
		$source_root_last =~ s|^.*/||;
		if ($source_root_last =~ /^(.+)_(.+?)(?:--(.*))?$/) {
			my ($module, $version, $extra) = ($1, $2, $3);
			$subdir = $extra; # the subdir is appended to the dir name
		} else {
			$subdir = '/'; # fake subdir for "things in the root"
		}
	}
	$self->update_index($subdir, $html_rel_path, $pod_name);
	#my $podpp_path = do_podpp($pod_path);
	do_mkdir($html_dir);
	do_pod2html(
		subdirs => $subdirs,
		source_root => $source_root,
		dest_root => $dest_root,
		dest_url => $dest_url,
		pod_path => $pod_path,
		html_path => $html_path,
	);
	#unlink $podpp_path;
	# postprocess HTML to add SSI tags for header and footer
    $self->postprocess_pod($html_path);
}

sub postprocess_pod {
	my ($self, $file) = @_;
	my $fh = new IO::File($file, 'r+')
		or die "Failed to open file '$file' for reading/writing: $!\n";
	my $title;
	my $text = "";
	my $in_body = 0;
	while (my $line = <$fh>) {
		if ($in_body) {
			if ($line =~ /^\s*<\/body>\s*$/) {
				$in_body = 0;
				next;
			}
			if ($line =~ /^\s*<hr \/>\s*$/) {
				next;
			}
			$text .= $line;
		} else {
			if ($line =~ /^\s*<body.*>\s*$/) {
				$in_body = 1;
				next;
			}
			if ($line =~ /\s*<title>(.*)<\/title>.*$/) {
				$title = $1;
			}
            elsif ($file =~ /\/(w+)\.html$/) {
                $title = $1;
            }
		}
	}
	seek $fh, 0, 0;
	truncate $fh, 0;
    #print $fh "<!--#set var=\"title\" value=\"$title\" -->", "\n" if defined $title;
    write_header($fh,$title);
    #print $fh '<!--#include virtual="/doc/cvs/header.html" -->' . "\n";
	print $fh $text;
    #print $fh '<!--#include virtual="/doc/cvs/footer.html" -->' . "\n";
    write_footer($fh);
	my $mode = (stat $fh)[2] & 0777 | 0111;
	chmod $mode, $fh;
}

sub update_index {
	my ($self, $subdir, $html_rel_path, $pod_name) = @_;
	$subdir =~ s|/.*$||;
	my $idx = $self->{idx};
	my $sections = $self->{section_hash};
	if (exists $sections->{$subdir}) {
		push @{$idx->{$subdir}}, [ $html_rel_path, $pod_name ];
	} else {
		warn "no section for subdir '$subdir'\n";
	}
}

sub write_index {
	my ($self, $out_path) = @_;
	my $idx = $self->{idx};
	my $sections = $self->{section_hash};
	my $section_order = $self->{section_order};
	my $source_root = $self->{source_root};
	$source_root =~ s|^.*/||;
	my $dest_url = $self->{dest_url};
	
	#print Dumper($idx);
	
	#my $header = "<html><head><title>Index $source_root</title></head><body>\n";
	#my $content_start = "<h1>Index for $source_root</h1><ul>\n";
	
    #my $header = qq|<!--#set var="title" value="Index for $source_root" -->| . "\n"
    #	. '<!--#include virtual="/doc/cvs/header.html" -->' . "\n";
    my $title = "Index for $source_root";
	my $content_start = "<ul>";
	my $content = "";
	
	foreach my $section (@$section_order) {
		next unless defined $idx->{$section};
		my $section_name = $sections->{$section};
		$content_start .= "<li><a href=\"#$section\">$section_name</a></li>\n";
		my @files = sort @{$idx->{$section}};
		$content .= "<a name=\"$section\"></a>\n";
		$content .= "<h2>$section_name</h2><ul>\n";
		foreach my $file (sort { $a->[1] cmp $b->[1] } @files) {
			my ($path, $name) = @$file;
			$content .= "<li><a href=\"$path\">$name</a></li>\n";
		}
		#$content .= "</ul><hr/>\n";
		$content .= "</ul>\n";
	}
	
	$content_start .= "</ul>\n";
	my $date = strftime "%a %b %e %H:%M:%S %Z %Y", localtime;
	my $content_end = "<p>Generated $date</p>\n";
	#my $footer = "</body></html>\n";
	#my $content_end = "";
    #my $footer = '<!--#include virtual="/doc/cvs/footer.html" -->' . "\n";
	
	my $fh = new IO::File($out_path, 'w') or die "Failed to open index '$out_path' for writing: $!\n";
    write_header($fh,$title);
    #print $fh $header, $content_start, $content, $content_end, $footer;
    print $fh $content_start, $content, $content_end;
    write_footer($fh);
	my $mode = (stat $fh)[2] & 0777 | 0111;
	chmod $mode, $fh;
}

sub do_podpp {
	my $in_path = shift;
	my $pp = make Pod::PP(-incpath=>[],-symbols=>{});
	#my ($out_fh, $out_path) = tempfile('ww-make-docs-podpp.XXXXXX');
	#local *STDOUT = $out_fh;
	my $out_path = "$in_path.podpp";
	local *STDOUT;
	open STDOUT, '>', $out_path or die "can't redirect STDOUT to $out_path: $!";
	$pp->parse_from_file($in_path);
	return $out_path;
}

sub do_mkdir {
	my $dir = shift;
	system '/bin/mkdir', '-p', $dir;
	if ($?) {
		my $exit = $? >> 8;
		my $signal = $? & 127;
		my $core = $? & 128;
		die "/bin/mkdir -p $dir failed (exit=$exit signal=$signal core=$core)\n";
	}
}

sub do_pod2html {
	my %o = @_;
	my @args = (
		defined $o{subdirs} && length $o{subdirs} ? "--podpath=$o{subdirs}" : (),
		"--podroot=$o{source_root}",
		"--htmldir=$o{dest_root}",
		defined $o{dest_url} && length $o{dest_url} ? "--htmlroot=$o{dest_url}" : (),
		"--infile=$o{pod_path}",
		"--outfile=$o{html_path}",
		'--recurse',
		'--noheader',
	);
	#print join(" ", 'pod2html', @args), "\n";
	pod2html(@args);
}

sub write_header {
	my $fh = shift;
    my $title = shift;
	print $fh qq{ 
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en" dir="ltr">
 <head>
  <!-- <base href="http://webwork.maa.org/" /> -->
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
  <link rel="shortcut icon" href="./favicon.ico" />
  <title>$title</title>
  <style type="text/css" media="screen,projection">/*<![CDATA[*/ \x40import "/w/skins/monobook/main.css?42b"; /*]]>*/</style>
  <link rel="stylesheet" type="text/css" media="print" href="/w/skins/common/commonPrint.css?42b" />
  <link rel="stylesheet" type="text/css" media="handheld" href="/w/skins/monobook/handheld.css?42b" />
  <!--[if lt IE 5.5000]><style type="text/css">\x40import "/w/skins/monobook/IE50Fixes.css?42b";</style><![endif]-->
  <!--[if IE 5.5000]><style type="text/css">\x40import "/w/skins/monobook/IE55Fixes.css?42b";</style><![endif]-->
  <!--[if IE 6]><style type="text/css">\x40import "/w/skins/monobook/IE60Fixes.css?42b";</style><![endif]-->
  <!--[if IE 7]><style type="text/css">\x40import "/w/skins/monobook/IE70Fixes.css?42b";</style><![endif]-->
  <!--[if lt IE 7]><script type="text/javascript" src="/w/skins/common/IEFixes.js?42b"></script>
  <meta http-equiv="imagetoolbar" content="no" /><![endif]-->
 </head>
 <body class="mediawiki ns-0 ltr page-Main_Page">
  <div id="globalWrapper">
   <div id="column-content">
	<div id="content">
     <a name="top" id="top"></a>
     <h1 class="firstHeading">$title</h1>
     <div id="bodyContent">
      <h3 id="siteSub">From WeBWorK</h3>
      <div id="contentSub"></div>
      <div id="jump-to-nav">Jump to: <a href="#column-one">navigation</a></div>
	  <!-- <base href="http://webwork.maa.org/pod/" /> -->
      <!-- start content -->
      }
}

sub write_footer {
	my $fh = shift;
	print $fh <<'EOF';
      <!-- end content -->
	  <!-- <base href="https://demo.webwork.rochester.edu/" /> -->
      <div class="visualClear"></div>
     </div>
	</div>
   </div>
   <div id="column-one">
	<div class="portlet" id="p-logo">
     <a style="background-image: url(http://webwork.maa.org/pod/webwork_square.png);" href="http://webwork.maa.org/wiki/Main_Page" title="Main Page"></a>
	</div>
	<script type="text/javascript"> if (window.isMSIE55) fixalpha(); </script>
	<div class='portlet' id='p-navigation-$module'>
	 <h5>Navigation</h5>
	 <div class='pBody'>
	  <ul>
	   <li><a href="https://demo.webwork.rochester.edu/wwdocs">Github Docs Home</a></li>
	   <li><a href="http://webwork.maa.org/wiki/Main_Page">WeBWorK Wiki</a></li>
	  </ul>
	 </div>
	</div>
EOF
	#for my $module (sort keys %index) {
		#print $fh "<div class='portlet' id='p-navigation-$module'>\n";
		#print $fh "<h5>$module</h5>\n";
		#print $fh "<div class='pBody'>\n";
		#print $fh "<ul>\n";
		#for my $version (reverse sort keys %{$index{$module}}) {
			#if (ref $index{$module}{$version}) {
				#print $fh "<li>$version<ul>\n";
				#for my $extra (sort keys %{$index{$module}{$version}}) {
					#print $fh "<li><a href=\"$BASE_URL/$index{$module}{$version}{$extra}\">$extra</a></li>\n";
				#}
				#print $fh "</ul></li>\n";
			#} else {
				#print $fh "<li><a href=\"$BASE_URL/$index{$module}{$version}\">$version</a></li>\n";
			#}
		#}
		#print $fh "</ul>\n";
		#print $fh "</div></div>\n";
	#}
	print $fh <<'EOF';
   </div><!-- end of the left (by default at least) column -->
   <div class="visualClear"></div>
   <script type="text/javascript">if (window.runOnloadHook) runOnloadHook();</script>
  </div>
 </body>
</html>

EOF
}

package main;

unless (caller) {
	unless (@ARGV >= 2) {
		print "usage: $0 source_root dest_root [ dest_url ]\n";
		exit 1;
	}
	my $htmldocs = new WeBWorK::Utils::HTMLDocs(
		source_root => $ARGV[0],
		dest_root => $ARGV[1],
		dest_url => $ARGV[2],
	);
	$htmldocs->convert_pods;
}

1;

