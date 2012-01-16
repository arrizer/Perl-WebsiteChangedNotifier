#!/usr/bin/perl

use WWW::Mechanize;
use Data::Dumper;
use Storable;
use Mail::Message;
use Mail::Transport::Sendmail;
use Digest::MD5 qw(md5_hex);
use XML::Simple;
use Getopt::Long;
use Encode;
use utf8;

# Switch standart out to UTF8
binmode STDOUT, ":utf8";

# Global options
our %options;						# Command line options
our $verbosity = 1;					# How much gobbling? (0 = none, 1 = medium, 2 = much)
our $config_file = "./config.xml";	# Location of the config.xml file
our $log_dir = ".";					# Log directory
our $store_dir = "./storage";		# Storage directory (downloaded html versions)
our $difftool = "diff";

our $config;	# Config hashref
our $pages;		# Pages hashref

get_options();
show_usage() if($options{"help"});
read_config();
diff_pages();
notify_users();
printv(1, "Done.");
exit();


sub notify_users{
	if($options{"no-notify"}){
		printv(1, "Skipping notifications.");
		return;
	}
	printv(1, "Notifying users...");
	my $users = $config->{"user"};
	for my $username(keys %$users){
		my $user = $users->{$username};
		my $subscriptions = $user->{"subscription"};
		my @changed_titles = ();
		my $message_subject = "";
		my $message_body = "One or more websites have changed since the last check:\n\n";
		printv(2, "\nAggregating subscriptions for user '".$username."'");
		for my $page_name(@$subscriptions){
			my $page = $config->{"page"}->{$page_name};
			if($page->{"changed"}){
				push(@changed_titles, $page->{"title"});
				$message_body .= $page->{"title"}." at ".$page->{"url"}." has changed.\n";
				$message_body .= "Diff output:\n".$page->{"diff"}."\n";
			}
		}
		
		if($#changed_titles == -1){
			printv(2, "No changes found for this user");
			next();
		}
		
		my $message_subject = join(", ", @changed_titles)." changed";
		$message_subject = Encode::encode("utf-8", $message_subject);
		printv(2, join(", ", @changed_titles)." changed for this user");
		
		my $sendmail = Mail::Transport::Sendmail->new(
			hostname 	=> $config->{"smtp_host"},
			username 	=> $config->{"smtp_user"},
			password 	=> $config->{"smtp_password"}
		);
		my $message = Mail::Message->build (
			From 		=> "Webchanged <webchanged@matthiasschwab.de>",
			To 			=> $user->{"email"},
			Subject 	=> $message_subject,
			data 		=> [ $message_body ],
		);
		printv(1, "Sending notification mail to '".$user->{"email"}."'");
		$sendmail->send($message);
	}
	return;
}

# Apply blacklist on content
sub apply_blacklist{
	my $content = shift;
	my $blacklist = $config->{"blacklist"};
	for my $item(@$blacklist){
		$content =~ s!$item->{"pattern"}!!gis;
	}
	return $content;
}

# Run diff on all pages
sub diff_pages{
	my $agent = WWW::Mechanize->new(autocheck => 0);
	my $tempfile = $store_dir."/_temp.txt";
	my $pages = $config->{"page"};
	for my $page_name(keys %$pages){
		my $page = $pages->{$page_name};
		printv(1, "\nChecking '".$page->{"title"}."'...");
		printv(2, "Fetching ".$page->{"url"});
		$agent->get($page->{"url"});
		my $content = apply_blacklist($agent->content());
		open(TEMP, ">", $tempfile);
		print TEMP $content; close TEMP;
		my $storagefile = $store_dir."/".$page_name.".html";
		if(!$agent->success()){
			printv(1, "Download failed! $!");
		}else{
			if(-e $storagefile){
				# Read the difftool output
				open(PIPE, $difftool." ".$tempfile." \"".$storagefile."\" |");
				my $diff = ""; $diff .= $_ while(<PIPE>); close PIPE;
				if($diff != ""){
					# Something changed
					$page->{"changed"} = 1;
					$page->{"diff"} = $diff;
					printv(1, '/!\ CHANGES FOUND');
					printv(2, "Difftool output: ".$diff);
				}else{
					printv(1, "Nothing changed");
				}
			}
			
			open(STORE, ">", $storagefile);
			print STORE $content;
			close STORE;
		}
	}
}

# Read the configuration files
sub read_config{
	$config = XMLin(
		$config_file, 
		ForceArray => ['regexp', 'page', 'user', 'blacklist']
	);
	$store_dir = $config->{"storage"} if($config->{"storage"});
	$log_dir = $config->{"logdir"} if($config->{"logdir"});
	$difftool = $config->{"difftool"};
}

# Print a line depending on verbosity
sub printv{
	my $min_verbosity = shift;
	my $message = shift;
	print($message."\n") if($verbosity >= $min_verbosity);
}

# Read flags and parameters from the command line
sub get_options{
	my $opt_verbose;

	my $result = GetOptions (
		"v|verbose" => \$options{"verbose"},
		"q|quiet" => \$options{"quiet"},
		"c|config=s" => \$options{"config"},
		"h|help" => \$options{"help"},
		"no-notify" => \$options{"no-notify"}
	);
	$verbosity = 2 if($options{"verbose"});
	$verbosity = 0 if($options{"quiet"});
	exit() if(!$result);
}

# Display the about screen and exit
sub show_usage{
	my $about = "
webchanged -- Version 0.1
Copyright (C) 2099 Matthias Schwab

Track website changes and notify subscribers by e-mail.
By default the script expects a config.xml in the working dir if not defined 
otherwise. See the comments in the default config file for its structure.

USAGE
      webchanged.pl [OPTIONS]

OPTIONS
      -v  --verbose       Verbose output
      -q  --quiet         No output at all
      -c  --config=FILE   Specify of config XML file
          --no-notify     Don't send any notification mails
      -h  --help          Display this help screen
";
	print($about);
	exit();
}
