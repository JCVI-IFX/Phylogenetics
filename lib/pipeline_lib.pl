use strict;

### SUBS START HERE ###

sub wait_for_grid_jobs_arrays {
# given an array of job_ids, wait until they are all done.
    my ($job_ids,$min,$max) = @_;

    my $lch = build_task_hash_arrays( $job_ids,$min, $max );
    my $stats_hash = build_task_hash_arrays($job_ids, $min, $max);

    while ( keys %{$lch} ) {
        for my $job_id ( keys %{$lch} ) {
            my $response = `qacct -j $job_id 2>&1`;
            parse_response_arrays( $response, $lch,$stats_hash );
            #print "Still waiting...\n";
            sleep 1;
        }
    }
}


sub parse_response_arrays {
# given a qacct response, delete a job id from the loop-control-hash when
# a statisfactory state is seen.
    my ( $response, $lch,$stats_hash ) = @_;
    return if ( $response =~ /error: job id \d+ not found/ );  # hasn't hit the grid yet.

    my @qacct_array = split ( /=+\n/, $response );
    @qacct_array = grep { /\S/ } @qacct_array; # get rid of empty record at beginning.
    
    for my $record ( @qacct_array ) {
        chomp $record;
        my @rec_array = split ( "\n", $record );
        my %rec_hash;

        for my $line (@rec_array) {
            $line =~ s/(.*\S)\s+$/$1/;
            my ( $key, $value ) = split ( /\s+/, $line, 2 );
            $rec_hash{ $key } = $value;
        }

        if ( defined $rec_hash{taskid} && defined $rec_hash{jobnumber} ) {
        my ($task_id, $job_id) = @rec_hash{'taskid','jobnumber'};
            unless ( $stats_hash->{ $job_id }->{ $task_id } ) {
                $stats_hash->{ $job_id }->{ $task_id } = \%rec_hash;

                # clear the task from the lch
                delete $lch->{ $job_id }->{ $task_id };

                # clear the job if all tasks are accounted for
                delete ( $lch->{ $job_id } ) unless ( keys %{ $lch->{ $job_id } } );
                print "Found task $task_id from job $job_id\n";
            }
        } else {
            print "Problem with one of the jobs' qacct info.\n";
        }
    }
}


sub build_task_hash_arrays {
    my ($job_ids, $min_id, $max_id) = @_;
    my $lch;
    
    for my $job_id ( @{$job_ids} ) {
        for my $task_id ( $min_id .. $max_id ) {
            $lch->{ $job_id }->{ $task_id } = 0;
        }
    }
    return $lch;
}


sub write_shell_script {
    my($dir,$program,$cmd) = @_;

    my $cmd_string = $cmd;
    my $script_name = "$dir/${program}_grid.sh";

    open ( my $gsh, '>', $script_name ) || die "Can't open $script_name: $!\n";

    select $gsh;

    print "#!/bin/tcsh\n\n";
    print "$cmd_string\n";

    close $gsh;
    select STDOUT;

    chmod 0755, $script_name;

    return $script_name;
}


sub launch_grid_job {
# Given a shell script, launch it via qsub.
    my ( $shell_script, $queue, $job_array_max, $dir, $grid_code, $cpu) = @_;

    my $qsub_command = "qsub -P $grid_code -o $dir -e $dir";
    $qsub_command .= " -l $queue" if ($queue ne "" && $queue);
    $qsub_command .= " -t 1-$job_array_max" if $job_array_max;
    $qsub_command .= " -pe threaded $cpu" if $cpu;

    $qsub_command .= " $shell_script";
    
    print "$qsub_command\n";
    
    my $response = `$qsub_command`;
    my $job_id;

    if ($response =~ (/Your job (\d+) \(.*\) has been submitted/) || $response =~ (/Your job-array (\d+)\./)) {

        $job_id = $1;
    
    } else {
        die "Problem submitting the job!: $response";
    }

    return $job_id;

}


sub parse_params_config {
	my $file = shift;
	my %params;
	
	open (IN, $file) || die "cannot open $file. $!\n";
	while (<IN>) {
		chomp $_;
		if ($_ =~ /^#/) {
			next;
		}
		my @line = split '\t', $_;
		
		$params{$line[0]}->{"flag"} = $line[1];
		$params{$line[0]}->{"value"} = $line[2];
	}
	close IN;
	return \%params;
}

sub read_shell_config {
	my $file = shift;
	my $text;
	
	open (IN, "$file") || die "Cannot open shell config file '$file'. $!\n";
	while (<IN>) {
		$text .= $_;	
	}
	close IN;
	
	$text .=  "\n";
	return $text;
}

sub write_bash_shell_script {
	my $file = shift;
	my $text = shift;

	open (OUT, ">$file") || die "Cannot write shell script '$file'. $!\n";
	print OUT $text;
	close OUT;
	
	chmod 0755, $file;
}

sub write_shell_template {
	my $file = shift;
	my $path = shift;
	my $shell_file_path = shift;
	
	my $new_file = "$shell_file_path/shell.template";
	
	my $text = &read_shell_config($file);
	
	$text =~ s/%PATH%/$path/g;
	
	&write_bash_shell_script($new_file, $text);
	
	return $new_file;
}


sub write_params_string {
	my $params = shift;
	my $string;
	
	foreach my $option (keys %$params) {
		if ($$params{"$option"}->{"value"}) {
			$string .= " " . $$params{"$option"}->{"flag"} . " " . $$params{"$option"}->{"value"};
		}
	}
	return $string;
}


sub write_list_file {
	my $file = shift;
	my $list = shift;
	
	open (OUT, ">$file") || die "cannot open $file. $!\n";
	foreach my $item (@$list) {
		print OUT "$item\n";
	}
}

sub read_list_file {
	my $list = shift;
	my @list;
	
	open (IN, $list) || die "Cannot open $list. $!\n";
	while (<IN>) {
		chomp $_;
		if (-e $_) {
			push @list, $_;
		} else {
			die "$_ does not exist.\n";
		}
	}
	close IN;
	return @list;
}

sub run_parser_script {
	my $shell_config = shift;
	my $results_path = shift;
	my $input_file = shift;
	my $parser = shift;
	my $snapshot_dir = shift;
	my $input_type = shift;
	
	my $shell_text = &read_shell_config($shell_config);
	my $shell_file = "$results_path/parser.sh";

	my $parsed_file = $input_file . ".parsed";
	my $parse_cmd = "$parser --input_file  $input_file --input_type $input_type --output_file $parsed_file --work_dir $snapshot_dir";
	$shell_text .= $parse_cmd;
	print "$shell_text\n";

	&write_bash_shell_script($shell_file,$shell_text);

	system $shell_file;
	return $parsed_file;
}

sub run_shell_script {
	my $cmd = shift;
	my $shell_config = shift;
	my $program = shift;
	my $results_path = shift;
	
	my $shell_text = &read_shell_config($shell_config);
	my $shell_file = "$results_path/$program.sh";
	
	$shell_text .= "$cmd\n";
	print $shell_text;
	
	&write_bash_shell_script($shell_file,$shell_text);

	system $shell_file;		
}

sub get_file_name {
	my $full_name = shift;
	
	my @parts = split '/', $full_name;
	my $file = pop @parts;	

	return $file;
}

sub cat_files {
	my $files = shift;
	my $file_name = shift;
	
	my $first_file = shift @$files;
	my $results = `cat $first_file > $file_name`;
	
	foreach my $file (@$files) {
		my $results = `cat $file >> $file_name`;
	}
}

sub print_time {
	my $stamp = shift;
	my $time = localtime(time);
	print "$stamp: $time\n";
	print "$ENV{HOST}\n";
}

sub get_lib_path {
	my $cfg = shift;
	my $service = shift;
	my $path;

	if ($cfg->val($service, 'unirefdb') eq 'UniRef90') {
		$path = "/usr/local/common/mgx-prok-annotation/3.0.0";
	} elsif ($cfg->val($service, 'unirefdb') eq 'UniRef100') {
		 $path = "/usr/local/common/mgx-prok-annotation/2.7.1"
	} else {
		$path = "/usr/local/common/mgx-prok-annotation/2.7.1";
	}

	return $path;
}

sub get_services {
	my $services_config = shift;
	my $dir = shift;
	my %EXECS;

	open (SERVICES, "$services_config") || die "cannot open $services_config";
	while (<SERVICES>) {
		chomp $_;
	
		my @line = split /\t/, $_;
		$EXECS{$line[0]}->{'cmd'} = "$FindBin::Bin/$line[1]";
		$EXECS{$line[0]}->{'dir'} = "$dir/$line[2]";
		#print "$line[0]\t$line[1]\t$line[2]\n";
	}
	close SERVICES;
	
	return %EXECS;
}

1;