#!/usr/local/bin/perl

=head1 NAME
    
    .pl
    
=head1 USAGE

    .pl [-]-results_path <results_path> [-]-infile <infile> [-]-project_code <project_code>

=head1 REQUIRED ARGUMENTS

=over

=item [-]-infile  <infile>

file containing a full path list of all multifasta files to process through the pipeline.

=for Euclid:
    infile.type: readable

=item [-]-results_path  <results_path>

full path to the location results files should be written

=for Euclid:
    results_path.type: string

=item [-]-project_code  <project_code>

charge code for using the grid

=for Euclid:
    project_code.type: string

=item [-]-service  <service>

service type to indicate where to look for optional parameter configurations

=for Euclid:
    service.type: string
    
=back

=head1 OPTIONS

=over

=item [-]-queue  <queue>

Specifies a queue for the grid jobs
   
=for Euclid:
    queue.type: string

=item [-]-config  <config>

Specifies a config file (ini format) used to overide standard pipeline configurations and default parameters

=for Euclid:
	config.type: string
	
=back

=head1 DESCRIPTION

This script will run .

=cut

use strict;
use Config::IniFiles;
use FindBin;
require "$FindBin::Bin/../lib/pipeline_lib.pl";

use lib "/usr/local/devel/VIRIFX/software/VGD/lib";
use Getopt::Euclid 0.2.4 qw(:vars);

my $infile = $ARGV_infile;
my $results_path = $ARGV_results_path;
my $queue = $ARGV_queue;
my $config = $ARGV_config;
my $grid_code = $ARGV_project_code;
my $service = $ARGV_service;

my $program_path = $0;
my @prog = split '/', $program_path;
my $program = pop @prog;

my $cfg;
if ($config) {
	$cfg = Config::IniFiles->new( -file => "$config" ) || die "cannot parse user suplied config file.\n";
}
my $cpu;
if ($cfg->val($service, 'cpu')) {
	$cpu = $cfg->val($service, 'cpu');
}

my $threads = $cpu*2;
my $beast_cmd = "java -Xmx13000m -Djava.library.path=/opt/software/beagle-lib-2.1.2/lib/ -jar /usr/local/packages/beast-1.8.2/lib/beast.jar -working";
if ($cpu) {
	$beast_cmd .= " -beagle_CPU";# -beagle_instances $cpu";# -beagle_scaling dynamic";
} else {
	$beast_cmd .= " -beagle_off";
}
$beast_cmd .= " $results_path/$infile";

print "$beast_cmd\n";

my $shell_name = "${program}";
my $sh_script = write_shell_script($results_path,$shell_name,$beast_cmd);

my $job_id = launch_grid_job( $sh_script, $queue, 1, $results_path, $grid_code, $cpu);

