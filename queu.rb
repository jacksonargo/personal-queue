#!/usr/bin/ruby -w

require 'yaml'

## Functions

# Print out a job entry
def print_job(job)
    printf "Name: %s\n", job[0]
    printf "    Summary: %s\n", job[1]["summary"]
    printf "    Priority: %i\n", job[1]["priority"]
    printf "    TTC: %i min\n", job[1]["ttc"]
end

# Sort all jobs by priority decreasing.
# Higher priority is more urgent, and lower ttc is better, so we sort by
# priority plus inverse of ttc. Then invert everything to reverse the sort.
def sort_jobs(all_jobs)
    all_jobs.sort_by { |m,k| 1.0/(k["priority"] + 1.0/k["ttc"]) }
end

# List all jobs
def list_jobs(all_jobs)
    sort_jobs(all_jobs).each { |a| print_job a }
end


# Insert a job into the queu.
# Either take the job info from options, or probe the user.
def add_job(all_jobs, name = nil, summary = nil, priority = nil, ttc = nil)
    # Check if we need to print help
    if name == "--help"
        puts "queu.rb add NAME SUMMARY PRIORITY TTC"
        exit
    end

    # Get the date; I'm not using this yet, but maybe soon.
    date = Time.now.strftime("%Y%m%d%H%M%S").to_i

    # Now we'll prompt the user for any info not passed as an argument.
    if name == nil
        printf "Name: "
        name = STDIN.gets.chomp
    end
    if summary == nil
        printf "Summary: "
        summary = STDIN.gets.chomp
    end
    if priority == nil
        printf "Priority (1-10): "
        priority = STDIN.gets.chomp
    end
    if ttc == nil
        printf "Estimated Time (min): "
        ttc = STDIN.gets.chomp
    end

    # Add the job to the list
    all_jobs[name] = {"summary" => summary, "date" => date,
                         "priority" => priority.to_i, "ttc" => ttc.to_i }
    # Write the list
    write_jobs all_jobs
end

# Remove a job from the queu
def del_job(all_jobs, name=nil)
    # Check if we need to print help
    if name == "--help"
        puts "queu.rb del NAME"
        exit
    end

    # Check if a name was provided
    if name == nil
        printf "Name of job to remove: "
        name = STDIN.gets.chomp
    end
    all_jobs.delete name
    # Write the list
    write_jobs all_jobs
end

# Pick a job from the queu
def pick_job(all_jobs, algorithm = nil)
    # Sort the jobs
    sorted = sort_jobs(all_jobs)

    # The default selection is "top"
    algorithm = "top" if algorithm == nil

    # Now we decide how to pick a job
    case algorithm
    when "top"
        # Simply print the highest priority job
        print_job sorted[0]
    when "high"
        # Choose a random job from the 5 highed priority
        x = 5 < sorted.length ? 5 : sorted.length
        print_job sorted[rand(x)]
    when "rand"
        # Choose a completely random job
        print_job sorted[rand(sorted.length)]
    else 
        puts "queu.rb pick [TOP|HIGH|RAND]"
        exit
    end
end

# Write jobs to file
def write_jobs (all_jobs)
    f = File.open($jobs_file, "w")
    f.write all_jobs.to_yaml
    f.close
end

##
## Main
##

# This is where the job data is stored.
$jobs_file=ENV['HOME']+'/.queu_jobs.yaml'

# Check that the file exists
unless File.exist? $jobs_file
    printf "The data file %s does not exist.\n", $jobs_file
    printf "Run 'touch %s' to create it.\n", $jobs_file
    exit 0
end

# Read in all the current jobs
all_jobs = YAML::load( File.open $jobs_file )

# Initialize all_jobs if the file was empty
if all_jobs == false
    puts "Initializing empty data file."
    all_jobs = {}
end

case ARGV[0]
when "add"
    add_job all_jobs, ARGV[1], ARGV[2], ARGV[3], ARGV[4]
when "del"
    del_job all_jobs, ARGV[1]
when "list"
    list_jobs all_jobs
when "pick"
    pick_job all_jobs, ARGV[1]
else
    puts "queu.rb [add|del|list|pick] [OPTIONS]"
end
