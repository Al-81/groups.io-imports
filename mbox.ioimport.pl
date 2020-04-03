#!/usr/bin/perl -w

# Import yahooGroup messages downloaded from Privacy Dashboard
# into groups.io via email direct-to-MX.
# Your IP-address must have RDNS; your ISP must not block port 25.
# How to check RDNS: on http://hostip.info there must be something after
# "Host name:", or else groups.io refuses mail directly from your computer.
# In such case you can run this program on a web-hosting,
# invoking it with a web-browser.

# This program can be used under Windows, MacOSX, Linux, FreeBSD etc.:
# 1. Unzip the download from Privacy Dashboard
# https://groups.yahoo.com/neo/getmydata
# (only the file messages.zip is used).
# 2. Create a directory (folder), if under Windows then C:\perl
# Everything will be in that directory.
# 3. (only Windows) download to that directory and unzip:
# (32bit) http://strawberryperl.com/download/5.14.4.1/strawberry-perl-5.14.4.1-32bit-portable.zip
# or (64bit) http://strawberryperl.com/download/5.14.4.1/strawberry-perl-5.14.4.1-64bit-portable.zip
# 4. Unzip the ioimport.zip file with this program
# and the messages.zip file (containing one or more files) into same directory.
# 5. Subscribe a new email address to the .io group, in Members set its
# display name to single dot. Messages from currently non-members
# and moderated members will be imported with that email address in "From:",
# original email address inserted into the top of message body.
# 6. From your group on groups.io website in Admin - Members right-click the
# Download button, save memberlist.csv into the same directory;
# 7. in Admin - Settings, Moderated must not be checked;
# 8. in Hashtags press Create Hashtag, enter #mi , check No Email
# and press Create Hashtag ("mi" means "message import").
# 9. Run this program (if under Windows then run portableshell.bat in that
# directory, type
# perl ioimport.pl
# and press Enter), it creates needchange.txt file with email addresses
# from the messages to import which are currently not subscribed
# to the .io group, or moderated, or have another problematic status.
# 10. You can optionally create (in the same directory) map.txt file,
# each line with two email addresses (separated with blanks, tabs or commas):
# email address in yahooGroup archive (from needchange.txt)
# and email address of the same person currently subscribed to the .io group.
# 11. Run the program again, look again into needchange.txt file.
# You can add to map.txt and run this program again several times.
# 12. In the same directory create file fromto.txt with one line with
# two email addresses: the email address you created and subscribed
# and email address of the .io group or subgroup.
# 13. Optionally run the program again, it sends an email to +help
# in order to check that it can email to groups.io directly from your computer
# (that your ISP doesn't block port 25 and your IP-address has RDNS).
# The mailbox you subscribed should receive an email with Subject beginning
# from "Automated help for the".
# 14. In the same directory create goahead.txt file (with empty content
# or any content).
# 15. Run this program again, import begins. If it fails, you can run
# this program again as many times as needed, it'll skip already imported
# messages and resume from the failed message.
# 16. Delete the fromto.txt, goahead.txt and imported.txt files
# and the files with .mbox. in their names extracted from messages.zip
# (they would be wrong if you want to import messages from another yahooGroup).
# 17. On groups.io website in Hashtags under #mi press Edit, Delete, Yes.

# version 7   22 December 2019   Lena@lena.kiev.ua   BSD license
# Perl 5 (any version)

use IO::Socket;
use strict;
my $delay = 50;   # seconds to wait between messages to avoid "500 We have
  # received more than 40 messages in 30 minutes from you. To guard against
  # autoresponder mail loops, we must reject additional messages from you
  # temporarily. Please try again later" - you can change to 0
my $mx = 'lb01.groups.io';   # instead of using Net::DNS possibly not installed
my $timeout = 20;   # seconds
my $debug = 0;   # set to 1 to see entire SMTP conversation
my $insert_date = 1;   # set to 0 to not insert Date into message body
print "Content-Type: text/plain\n\n";   # for case if called by a web-server

my ($emailLine, $dayString, $monthString, $dateNum, $Time, $Year); # added these for clarity in splitting From string
my $detailDebug = 1; # added debug sub for standard printing of details when troubleshooting
my $debugMessage = "no string passed"; #  added declaration of detailed string message

open( ML, 'memberlist.csv' ) or die "File memberlist.csv not found\n";
die "Wrong memberlist format\n" unless <ML> =~ /^Email,/;
my %ml;
while ( <ML> ) {
  s/\s+$//;
  my( $member_email,
      undef,   # Display Name
      undef,   # Username
      undef,   # Joined
      $status, # 0=Normal,1=Pending,2=Banned
      $po_st,  # 0=Normal,1=Allowed,2=Moderated,3=NotAllowed,4=NewUserModerated
      undef,   # Email Delivery(0=Single,1=Plain Digest...
      undef,   # Message Selection(0=All,1=Follow Only,...
      undef,   # Auto Follow Replies
      undef,   # Mod Status(0=None,1=Moderator,2=Owner)
      $us_st   # 0=Not Confirmed,1=Confirmed,2=Inactive,3=Bouncing,4=Bounced
    ) = split /,/ ;
  $ml{lc($member_email)} = $status . $po_st . $us_st;
} 
close ML;
my %map;
if ( open( MAP, 'map.txt' )) {
  while ( <MAP> ) {
    next if /^\s*$/;
    die "Wrong map format\n" unless /^\s*(\S+)[\s,]+(\S+)\s*$/;
    $map{lc($1)} = $2;
  }
  close MAP;
}
my $needconnect = 0;
my( $from, $to );
if ( open( ADDR, 'fromto.txt' )) {
  $needconnect = 1;
  die "fromto.txt must contain two email addresses\n" unless
         <ADDR> =~ /\s*(\S+\@\S+)[\s,]+(\S+\@\S*groups.io)\s*$/;
  $from = $1; $to = $2;
  die "first address in fromto.txt must be unmoderated\n" unless
       $ml{lc($from)} =~ /^0[01]1/;
  close ADDR;
}
my $goahead = $needconnect && -e 'goahead.txt';
print "Please wait...\n\n";
my( $line, $sock );
my $imported = 0;
my $inmailfrom = 0;
print "CHecking needconnect $needconnect\n";
if ( $needconnect ) { print "True\n"; } else { print " False \n"; }



if ( $needconnect ) {
   #Checking on number of previously imported emails?
  if ( open( N, 'imported.txt' )) {
    $_ = <N> || '0';
    s/[\r\n]+$//;
    $imported = 0 + $_;
    close N;
  }
  &conn;
  unless ( $goahead ) {
    &ioct( 'w', "MAIL FROM:<$from>\015\012" );
    $line = &ioct( 'r' );
    die "after MAIL FROM: $line" unless $line =~ /^2/;
    $to =~ s/\@/\+help\@/;
    &ioct( 'w', "RCPT TO:<$to>\015\012" );
    $line = &ioct( 'r' );
    die "after RCPT TO: $line" unless $line =~ /^2/;
    &ioct( 'w', "DATA\015\012" );
    $line = &ioct( 'r' );
    die "after DATA: $line" unless $line =~ /^354/;
    &ioct( 'w', "From: $from\015\012" .
                "To: $to\015\012" .
                "Subject: -\015\012" .
                "\015\012" .
                "-\015\012" .
                ".\015\012" );
    $line = &ioct( 'r' );
    die "after sending the test email: $line" unless $line =~ /^2/;
    print "Email to $to sent.\n";
    &quit;
    exit;
  }
}
opendir( D, '.' );

# Create an array of all the *.mbox files in the current directory
my @mbox_parts = sort( grep { /\.mbox/ } readdir D );
closedir D;

my @emails = ();
my( $email, @header, $fromchanged,
    @boundaries, $text, $base64, $partheader, $original, $hassubject, $date );
my $messages = 0;
my $processing_message = 0;

# Process each .mbox file
foreach my $mbox_part ( @mbox_parts ) {
   debugMsg ("Processing file ... $mbox_part");
  open( MBOX, $mbox_part );
  my $in_header = 0;
  my $deleted = 1;
  #  reading each emailLine of the file
  while ( $emailLine = <MBOX> ) {
  #while ( <MBOX> ) {
    #s/[\r\n]+$//;
    $emailLine =~ s/[\r\n]+//;
    my $lineLength = length $emailLine;
    debugMsg ("Length of emailLine $lineLength");
    if ( $emailLine =~ /^From /) {
         (undef, $email, $dayString, $monthString, $dateNum, $Time, $Year) = split(/\s+/,$emailLine); 
  #   debugMsg ( "Found From emailLine,\n\t email $email
  #  dayString $dayString
  # monthString $monthString
  # dateNum $dateNum
  #  Time $Time
  #  Year $Year\n");
       #if ( /^From (\S+) ([A-Z][a-z]{2} ){2}\d\d \d\d:\d\d:\d\d \d{4}$/ ) {
       #$email = $1;
      $original = "From: $email";
      $in_header = 1;
      $deleted = 0;
      @header = ();
      $fromchanged = 0;
      @boundaries = ();
      $text = 'plain';
      $base64 = 0;
      $partheader = 0;
      $processing_message = 1;
      $hassubject = 0;
      debugMsg ("From emailLine parsed, set the following\n
      email $email
      in_header $in_header
      deleted $deleted
      fromchanged $fromchanged
      text $text
      base64 $base64 ;
      partheader $partheader;
      processing_message $processing_message;
      hassubject $hassubject")
    }
    elsif ( $in_header ) {
      next if $deleted;
      #if ( 0 == length ) {   # empty emailLine after header
      if ( 0 == $lineLength ) {  #updated to use $emailLine in place of $_ 
        #debugMsg ("Found length 0 emailLine $emailLine");
        $in_header = 0;
        $email =~ s/^<//;
        $email =~ s/[>\)]$//;
        if ( $email =~ /\@([x.]+)$/ ) {
          my $domain = $1;
          $domain =~ s/x{2,}/x/g;
          $email =~ s/\@[x.]+$/\@$domain/;
        }
        my $mapel = $map{lc($email)};
        $email = $mapel, $fromchanged = 1 if defined $mapel;
        my $lcemail = lc $email;
        my $found = 0;
        foreach my $already ( @emails ) {
          $found = 1, last if $lcemail eq lc $already;
        }
        push( @emails, $email ) unless $found;
        &finish1;
        if ( $goahead and $messages > $imported ) {
          my $statuses = $ml{$lcemail};
          $email = $from, $fromchanged = 1 unless defined( $statuses ) and
               $statuses =~ /^0[01]1/;
          for ( my $i = 0; ; $i++ ) {
            &ioct( 'w', "MAIL FROM:<$email>\015\012" );
            $inmailfrom = 1;
            $line = &ioct( 'r' );
            $inmailfrom = 0;
            last if defined $line;
            die "connection broken after MAIL FROM, 5 retries failed\n"
                if $i == 5;
            close $sock;
            &conn;
          }
          die "after MAIL FROM: $line" unless $line =~ /^2/;
          &ioct( 'w', "RCPT TO:<$to>\015\012" );
          $line = &ioct( 'r' );
          die "after RCPT TO: $line" unless $line =~ /^2/;
          &ioct( 'w', "DATA\015\012" );
          $line = &ioct( 'r' );
          die "after DATA: $line" unless $line =~ /^354/;
          $sock->autoflush( 0 );
          my $name = '';
          $original = '';
          $date = '';
          foreach $line ( @header, '' ) {
            if ( $line =~ /^(\S+)\s*:/ or $line eq '' ) {
              if ( $name eq 'from' and $fromchanged ) {
                &ioct( 'w', " <$email>\015\012" );
              }
              if ( $name eq 'subject' ) {
                &ioct( 'w', " #mi\015\012" );
                $hassubject = 1;
              }
              $name = lc $1 if defined $1;
            }
            $line .= ' -' if $line =~ /^subject:\s*$/i;
            if ( $name eq 'from' and $fromchanged and $line ne '' ) {
              $original .= $line;
              $line =~ tr/<>()@/_/;
            }
            if ( $line eq '' and not $hassubject ) {
              &ioct( 'w', "Subject: (no subject) #mi\015\012" );
            }
            if ( $name eq 'date' and $line ne '' ) {
              $date .= $line;
            }
            &ioct( 'w', "$line\015\012" );
          }
          &insert;
        }
      }
      elsif ( $email =~
                 /^(yahoo-dev-null|no_reply)\@(yahoo-inc|(e|yahoo)groups).com$/
              and /^From: ([^@\s]+)($| <no_reply\@(e|yahoo)groups.com>)/ ) {
        $email = $1 . '@yahoo.com';
        push @header, $_;
        $fromchanged = 1;
      }
      elsif ( /^X-Deleted-Message: yes/ ) {
        $deleted = 1;
      }
      else {
        &boundary_text_base64;
        push @header, $_;
      }
    }
    else {   # in body
      debugMsg ("processing Body!$emailLine");
        next if $deleted;
      if ( $goahead and $messages > $imported ) {
        if ( /--\S/ ) {
          foreach my $boundary ( @boundaries ) {
            if ( /^--$boundary$/ ) {
              $partheader = 1;
              $text = '';
              $base64 = 0;
            }
          }
        }
        s/^\./../;
        &ioct( 'w', "$_\015\012" );
        if ( $partheader ) {
          if ( 0 == length ) {
            &insert;
            $partheader = 0;
          }
          &boundary_text_base64;
        }
      }
    }
  }
  close MBOX;
}
&finish1;
$messages--;
&quit if $goahead and $processing_message;

open( CH, '>needchange.txt' );
my $num = 0;
foreach $email ( sort @emails ) {
  $num++;
  my $statuses = $ml{lc($email)};
  if ( not defined $statuses  ) { print CH "NotMember        $email\n"; }
  elsif ( $statuses =~ /^1/   ) { print CH "Pending          $email\n"; }
  elsif ( $statuses =~ /^2/   ) { print CH "Banned           $email\n"; }
  elsif ( $statuses =~ /^..0/ ) { print CH "NotConfirmed     $email\n"; }
  elsif ( $statuses =~ /^..2/ ) { print CH "Inactive         $email\n"; }
  elsif ( $statuses =~ /^..3/ ) { print CH "Bouncing         $email\n"; }
  elsif ( $statuses =~ /^..4/ ) { print CH "Bounced          $email\n"; }
  elsif ( $statuses =~ /^.2/  ) { print CH "Moderated        $email\n"; }
  elsif ( $statuses =~ /^.3/  ) { print CH "NotAllowedToPost $email\n"; }
  elsif ( $statuses =~ /^.4/  ) { print CH "NewUserModerated $email\n"; }
  else { $num-- }
}
close CH;
print "$imported messages imported earlier\n" if $imported;
print "total $messages messages (deleted messages excluded)";
print ' imported' if $goahead;
print "\n$num email addresses ";
print 'need to be ' unless $goahead;
print "changed, see needchange.txt\n";

sub ioct {   # I/O, check timeout
  my $result;
  print $_[1] if $debug and $_[0] eq 'w';
  eval {
    alarm $timeout;
    $result = $_[0] eq 'r' ? <$sock> : print( $sock $_[1] );
    alarm 0;
  };
  if ( $@ ) {
    die unless $@ eq "alarm\n";   # propagate unexpected errors
    die( 'timeout ', $_[0] eq 'w' ? 'sending to' :
         'reading from', " groups.io's mail server\n" );
  }
  else {
    die "connection broken\n" unless defined( $result ) or $inmailfrom;
    if ( $debug ) {
      if ( defined $result ) {
        print $result if $_[0] eq 'r';
      }
      else {
        print "connection broken\n";
      }
    }
    return $result;
  }
}
sub conn {
  $sock = IO::Socket::INET->new( 'PeerAddr'   => $mx,
                                 'PeerPort'   => 25,
                                 'Proto'      => 'tcp',
                                 'MultiHomed' => 1,
                                 'Timeout'    => $timeout );
  die "Cannot connect to port 25 at $mx: $!\nMay be your ISP blocks port 25.\n"
       unless $sock;
  $line = &ioct( 'r' );
  die "at connection: $line" unless $line =~ /^2/;
  &ioct( 'w', "HELO import.messages.from.yahoogroups\015\012" );
  $line = &ioct( 'r' );
  die "after HELO: $line" unless $line =~ /^2/;
}
sub insert {
  if ( $text =~ /plain|html/ and $fromchanged || $insert_date ) {
    my $what = '';
    $what = $original if $fromchanged;
    if ( $fromchanged and $insert_date ) {
      $what .= '<br>' if $text eq 'html';
      $what .= "\015\012";
    }
    $what .= $date if $insert_date;
    $what .= '<br><br>' if $text eq 'html';
    $what .= "\015\012";
    if ( $base64 ) {
      $what = substr( pack( 'u', substr( $what . ' ' x 45, 0, 45 )), 1, 60 );
      $what =~ tr|` -_|AA-Za-z0-9+/|;
    }
    &ioct( 'w', "$what\015\012" );
  }
}
sub boundary_text_base64 {
  if ( /boundary=["']?([^"'\s]+)/ ) {
    push @boundaries, $1;
  }
  if ( m!text/(plain|html)! ) {
    $text = $1;
  }
  if ( /^content-transfer-encoding:\s*base64/i ) {
    $base64 = 1;
  }
}
sub finish1 {
  if ( $processing_message ) {
    if ( $messages++ > $imported and $goahead ) {
      $sock->autoflush( 1 );
      &ioct( 'w', ".\015\012" );
      $line = &ioct( 'r' );
      die "after sending message $messages: $line" unless $line =~ /^2/;
      open( N, '>imported.txt' );
      print N $messages;
      close N;
      print "$messages\n" if $messages % 100 == 0;
      sleep $delay if $delay;
    }  
  }
}
sub quit {
  &ioct( 'w', "QUIT\015\012" );
  $line = &ioct( 'r' );
  close $sock;
}

sub debugMsg {
  if ($detailDebug) {
	print "DEBUG: $_[0] \n\t End Debug message\n";
		}
}



# ~ $ telnet lb01.groups.io 25
# Trying 45.79.81.153...
# Connected to lb01.groups.io.
# Escape character is '^]'.
# 220 groups.io ESMTP ready
# HELO import.messages.from.yahoogroups
# 250 groups.io
# MAIL FROM:<Lena@lena.kiev.ua>
# 250 2.0.0 OK
# RCPT TO:<GROUPNAME@groups.io>
# 250 Accepted
# DATA
# 354 Enter message, ending with "." on a line by itself
# Subject: test
# 
# -
# .
# 250 OK
# QUIT
# 221 Bye
# Connection closed by foreign host.
# ~ $

