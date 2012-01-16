This script allows you to monitor changes to a website and send e-mail notifications to subscribers when they do.

INSTALLATION

(1) Copy the script somewhere and remote .template from the config file.
Add some websites and subscribers to the config.xml (see documentation in the XML file)

(2) Make sure you have the required perl modules installed by running:

$ sudo sh -c "curl -L cpanmin.us | perl - WWW::Mechanize Data::Dumper Storable Mail::Message Mail::Transport::Sendmail Digest::MD5 XML::Simple Getopt::Long Encode"

(3) Add the script to the crontab (or any other task scheduler you like) to run hourly (make sure the crontab user is allowed to send mails via the configured mail SMTP server)