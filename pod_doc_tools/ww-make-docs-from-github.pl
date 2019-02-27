#!/usr/bin/perl -sT
################################################################################
# WeBWorK Online Homework Delivery System
# Copyright © 2000-2003 The WeBWorK Project, http://openwebwork.sf.net/
# $CVSHeader: admintools/ww-make-docs-from-cvs,v 1.5 2007/10/02 20:27:44 sh002i Exp $
# 
# This program is free software; you can redistribute it and/or modify it under
# the terms of either: (a) the GNU General Public License as published by the
# Free Software Foundation; either version 2, or (at your option) any later
# version, or (b) the "Artistic License" which comes with this package.
# 
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See either the GNU General Public License or the
# Artistic License for more details.
################################################################################

=head1 NAME

ww-make-docs-from-cvs - make WeBWorK documentation from github viewable over the web

=cut

use 5.10.0;
use strict;
use warnings;
use IO::File;

$ENV{PATH} = "";
$ENV{ENV} = "";

our $CHECKOUT_DIR = '/home/mgage/webwork_masters/ww_source_files';
our $DOC_DIR = '/home/mgage/htdocs/wwdocs';

our $GIT = "/usr/bin/git";
our $MKDIR = "/bin/mkdir";
our $RM = "/bin/rm";
our $WW_MAKE_DOCS = '/home/mgage/webwork_masters/pod_doc_tools/ww-make-docs.pl';

our $BASE_URL = 'https://demo.webwork.rochester.edu/wwdocs';

our $v; # for verbose switch

my @dirs;
my %index;

if (@ARGV) {
	@dirs = map "$CHECKOUT_DIR/$_", @ARGV;
} else {
	@dirs = glob("$CHECKOUT_DIR/*");
}
say "directories to update from ". join("\n\t ", @dirs);
foreach my $dir (@dirs) {
	next unless -d $dir;
	say "reading $dir";
	if ($dir =~ m/^([^\!\$\^\&\*\(\)\~\[\]\|\{\}\'\"\;\<\>\?]+)$/) {
		print "\n-----> $dir <-----\n\n" if $v;
	#	update_git($1);
		process_dir($1);
		update_index($1);
	} else {
		warn "'$dir' insecure.\n";
	}
}

{
	my $fh = new IO::File("$DOC_DIR/index.html", 'w')
		or die "failed to open '$DOC_DIR/index.html' for writing: $!\n";
    write_index_new($fh);
    #write_index($fh);
	my $mode = (stat $fh)[2] & 0777 | 0111;
	chmod $mode, $fh;
}

sub update_git {
	my ($dir) = @_;
	
	system "cd \"$dir\" && $GIT pull" and die "git failed: $!\n";
}

sub process_dir {
	my ($source_dir) = @_;
	my $dest_dir = $source_dir;
	$dest_dir =~ s/^$CHECKOUT_DIR/$DOC_DIR/;
	
	system $RM, '-rf', $dest_dir;
	system $MKDIR, '-p', $dest_dir;
	if ($?) {
		my $exit = $? >> 8;
		my $signal = $? & 127;
		my $core = $? & 128;
		die "/bin/mkdir -p $dest_dir failed (exit=$exit signal=$signal core=$core)\n";
	}
	
	system $WW_MAKE_DOCS, $source_dir, $dest_dir;#, $BASE_URL;
	if ($?) {
		my $exit = $? >> 8;
		my $signal = $? & 127;
		my $core = $? & 128;
		die "$WW_MAKE_DOCS $source_dir $dest_dir failed (exit=$exit signal=$signal core=$core)\n";
	}
}

sub update_index {
	my $dir = shift;
	$dir =~ s/^.*\///;
	if ($dir =~ /^(.+)_(.+?)(?:--(.*))?$/) {
		my ($module, $version, $extra) = ($1, $2, $3);
		if ($version =~ /^rel-(\d+)-(\d+)(?:-(\d+))?$/) {
			my ($major, $minor, $patch) = ($1, $2, $3);
			if (defined $patch) {
				$version = "$major.$minor.$patch";
			} else {
				$version = "$major.$minor.0";
			}
		} elsif ($version =~ /^rel-(\d+)-(\d)-(?:patches|dev)$/) {
			my ($major, $minor) = ($1, $2);
			$version = "$major.$minor.x (bugfixes)";
		} elsif ($version eq "develop") {
			$version = 'develop';
		} else {
			warn "unfamiliar version string '$version' for dir '$dir' -- not adding to index.\n";
			return;
		}
		$module =~ s/^pg$/PG/;
		$module =~ s/^webwork2$/WeBWorK/;
		$module =~ s/^OpenProblemLibrary/OPL/;
		if (defined $extra) {
			$index{$module}{$version}{$extra} = $dir;
		} else {
			$index{$module}{$version} = $dir;
		}
	} else {
		warn "unfamiliar dir format '$dir' -- not adding to index.\n";
	}
}

sub write_index {
	my $fh = shift;
	print $fh "<html><head><title>WeBWorK Documentation from Git</title></head><body>\n";
	print $fh "<h1>WeBWorK Documentation from Git</h1>\n";
	print $fh "<ul>\n";
	print $fh map { "<li><a href=\"#$_\">$_</a></li>\n" } sort keys %index;
	print $fh "</ul>\n";
	for my $module (sort keys %index) {
		print $fh "<hr/>\n";
		print $fh "<h2><a name=\"$module\">$module</a></h2>\n";
		print $fh "<ul>\n";
		for my $version (sort keys %{$index{$module}}) {
			if (ref $index{$module}{$version}) {
				print $fh "<li>$version<ul>\n";
				for my $extra (sort keys %{$index{$module}{$version}}) {
					print $fh "<li><a href=\"$index{$module}{$version}{$extra}\">$extra</a></li>\n";
				}
				print $fh "</ul></li>\n";
			} else {
				print $fh "<li><a href=\"$index{$module}{$version}\">$version</a></li>\n";
			}
		}
		print $fh "</ul>\n";
		print $fh "</body></html>\n";
	}
}

sub write_index_new {
	my $fh = shift;
    write_header($fh, 'WeBWorK Documentation from Git');
	print $fh "<h2>Main Menu</h2>\n";
	print $fh '<p>Chose a product and version from the menu to the left.</p>';
    write_footer($fh);
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
  <!--[if lt IE 7]><script type="text/javascript" src="/skins/common/IEFixes.js?42b"></script>
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
	  <!-- <base href="https://demo.webwork.rochester.edu/wwdocs/" /> -->
      <!-- start content -->
      }
}

sub write_footer {
	my $fh = shift;
	print $fh <<'EOF';
      <!-- end content -->
	  <!-- <base href="https://demo.webwork.rochester.edu/wwdocs/" /> -->
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
	   <li><a href="pg">PG</a></li>
	   <li><a href="webwork2">WeBWorK2</a></li>
	  </ul>
	 </div>
	</div>
EOF
	for my $module (sort keys %index) {
		print $fh "<div class='portlet' id='p-navigation-$module'>\n";
		print $fh "<h5>$module</h5>\n";
		print $fh "<div class='pBody'>\n";
		print $fh "<ul>\n";
		for my $version (reverse sort keys %{$index{$module}}) {
			if (ref $index{$module}{$version}) {
				print $fh "<li>$version<ul>\n";
				for my $extra (sort keys %{$index{$module}{$version}}) {
					print $fh "<li><a href=\"$BASE_URL/$index{$module}{$version}{$extra}\">$extra</a></li>\n";
				}
				print $fh "</ul></li>\n";
			} else {
				print $fh "<li><a href=\"$BASE_URL/$index{$module}{$version}\">$version</a></li>\n";
			}
		}
		print $fh "</ul>\n";
		print $fh "</div></div>\n";
	}
	print $fh <<'EOF';
   </div><!-- end of the left (by default at least) column -->
   <div class="visualClear"></div>
   <script type="text/javascript">if (window.runOnloadHook) runOnloadHook();</script>
  </div>
 </body>
</html>

EOF
}
