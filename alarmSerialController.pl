#!/usr/bin/perl

use Device::SerialPort;
use MIME::Lite;
use Time::HiRes qw(usleep);
use DBI;

my $port;
my $status = "OFFLINE";
my $sensor = "CLOSE";
my $lastStatus = "NONE";
my $ready = 0;
my $dbUrl = "DBI:mysql:database=aalarm;host=localhost";
my $dbLogin = "aalarm";
my $dbPasswd = "wont6Oc`";
my $statusLevel = 1;
my $sensorState = 1;
my $lastStatusLevel = 1;
my $lastSensorState = 1;
my $pathWebCommand = "/home/kemkem/AAlarm/web/command/command";
my $pathWebStatus = "/home/kemkem/AAlarm/web/state";
my $pathLog = "/home/kemkem/AAlarm/log";
my $reconnectTimeout = 5;

sub recordEvent
{
	my $status = shift;
	my $state = shift;
	my $dbh = DBI->connect($dbUrl, $dbLogin, $dbPasswd, {'RaiseError' => 1});
        $dbh->do("insert into Event (date, status, sensor) values (now(), $status, $state)");
}

sub recordFailure
{
	my $dbh = DBI->connect($dbUrl, $dbLogin, $dbPasswd, {'RaiseError' => 1});
        $dbh->do("insert into Event (date, status, sensor) values (now(), 1, 1)");
}

sub getCurDate
{
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$mon = sprintf("%02d", $mon);
	$mday = sprintf("%02d", $mday);
	$year = sprintf("%02d", $year % 100);
	$hour = sprintf("%02d", $hour);
	$min = sprintf("%02d", $min);
	$sec = sprintf("%02d", $sec);
	#$year += 1900;
	return $mon."/".$mday."/".$year." ".$hour.":".$min.":".$sec;
}

sub recordLog
{
	my $log = shift;
	open LOG, ">>".$pathLog;
	print LOG getCurDate()." ".$log."\n";
	close LOG;
}

sub getCommand
{
	my $dbh = DBI->connect($dbUrl, $dbLogin, $dbPasswd, {'RaiseError' => 1});
        my $prepare = $dbh->prepare("
	select c.command as command
	from Commands c
	where c.completed  = 0
	ORDER BY c.id DESC
	LIMIT 0 , 1");
	$prepare->execute() or die("cannot execute request\n");
	my $result = $prepare->fetchrow_hashref();
	if ($result)
	{
		my $command = $result->{command};
		recordLog("C [".$command."]");

	        $dbh->do("update Commands set completed=1 where completed=0");

		return "setOnline" if ($command =~ /setOnline/);
		return "setOffline" if ($command =~ /setOffline/);
	}
	else
	{
		return "status";
	}
	
}

while (1)
{
	recordLog ">Trying to connect...";
	if ($port = Device::SerialPort->new("/dev/ttyACM0"))
	{
		recordLog ">Success";
		$port->databits(8);	
		$port->baudrate(9600);
		$port->parity("none");
		$port->stopbits(1);

		my $count = 0;
		my $connection = 5;

		while ($connection > 1) {
		    my $response = $port->lookfor();

		    if ($response) {
			chop $response;
			$connection++;
			#print "R [".$response."]\n";
			if($response =~ /READY/)
			{
				$ready = 1;
			}
			else
			{
				$response =~ /STATUS:(.*)\|(.*)/;
				open FILE, ">".$pathWebStatus;
				print FILE $response;
				close FILE;	
				
				$status = $1;
				$sensor = $2;
				$statusLevel = 1;
				$sensorState = 1;
				#record status in db
				if ($status =~ /OFFLINE$/)
				{
					$statusLevel = 2;
				}
				elsif ($status =~ /ONLINE$/)
				{
					$statusLevel = 3;
				}
				elsif ($status =~ /ONLINE_TIMED$/)
				{
					$statusLevel = 7;
				}
				elsif ($status =~ /INTRUSION$/)
				{
					$statusLevel = 4;
				}
				elsif ($status =~ /INTRUSION_WARNING/)
				{
					$statusLevel = 5;
				}
				elsif ($status =~ /INTRUSION_ALARM/)
				{
					$statusLevel = 6;
				}
				#record sensor in db
				if ($sensor =~ /CLOSE$/)
				{
					$sensorState = 2;
				}
				elsif ($sensor =~ /OPEN$/)
				{
					$sensorState = 3;
				}
				
				if ($lastStatusLevel != $statusLevel)
				{
					recordEvent($statusLevel, $sensorState);
					recordLog "R [STATUS $status]";
				}
				if ($lastSensorState != $sensorState)
				{
					recordEvent($statusLevel, $sensorState);
					recordLog "R [STATE $sensor]";
				}
				$lastStatusLevel = $statusLevel;
				$lastSensorState = $sensorState;
				
			}
		    } else {
			sleep(1);

			$nextCommand = getCommand();

			#if(-f $pathWebCommand)
			#{
			#	recordLog "C [reading command]\n";
			#	open COMMAND_FILE, $pathWebCommand;
			#	while(<COMMAND_FILE>)
			#	{
			#		$nextCommand = "setOnline" if (/setOnline/);
			#		$nextCommand = "setOffline" if (/setOffline/);
			#	}
			#	close COMMAND_FILE;
			#	unlink $pathWebCommand or die "Error : cannot delete command file\n";
			#}

			if ($lastStatus =~ /ONLINE$/ && $ready == 1)
			{
				$send = "setOnline";
				$lastStatus = "NONE";
			}
			elsif ($lastStatus =~ /ONLINE_TIMED$/ && $ready == 1)
			{
				$send = "setOnlineTimed";
				$lastStatus = "NONE";
			}
			elsif ($lastStatus =~ /INTRUSION$/ && $ready == 1)
			{
				$send = "setOnlineIntrusion";
				$lastStatus = "NONE";
			}
			elsif ($lastStatus =~ /INTRUSION_WARNING/ && $ready == 1)
			{
				$send = "setOnlineWarning";
				$lastStatus = "NONE";
			}
			elsif ($lastStatus =~ /INTRUSION_ALARM/ && $ready == 1)
			{
				$send = "setOnlineAlarm";
				$lastStatus = "NONE";
			}
			else
			{
				$send = $nextCommand;
			}
			$port->write($send."\n");
			#print "S [".$send."]\n";
			$connection--;
		    }						
		}
		recordLog "Connection has been lost!";
		recordLog "last state was $status";
		recordFailure();
		$statusLevel = 1;
		$sensorState = 1;
		$lastStatusLevel = 1;
		$lastSensorState = 1;
		#$status = "UNK";
		#$sensor = "UNK";
		$lastStatus = $status;
		$ready = 0;
	}
	else
	{
		recordLog ">Cannot connect, retrying in $reconnectTimeout second...";
		sleep($reconnectTimeout);
	}

}

