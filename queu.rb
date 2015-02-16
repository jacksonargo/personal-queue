#!/usr/bin/ruby -w

require 'yaml'

## Functions

## Get the date and time formatted as an integer
def get_time
    return Time.now.strftime("%Y%m%d%H%M%S").to_i
end

## Print out a job entry
def print_job(job)
    printf "Name: %s\n", job[0]
    printf "    Summary: %s\n", job[1]["summary"]
    printf "    Priority: %i\n", job[1]["priority"]
    printf "    TTC: %i min\n", job[1]["ttc"]
    printf "    Added: %i\n", job[1]["added"]
    printf "    Completed: %i\n", job[1]["completed"] if job[1]["completed"] != nil
end

## Sort all jobs by priority decreasing.
# Higher priority is more urgent, and lower ttc is better, so we sort by
# priority plus inverse of ttc. Then invert everything to reverse the sort.
# Returns an array.
def sort_jobs(all_jobs)
    return all_jobs.sort do |x,y| 
        # First we check if the jobs have been completed
        if x[1]["completed"] == nil and y[1]["completed"] != nil
            -1
        elsif x[1]["completed"] != nil and y[1]["completed"] == nil
            1
        # For uncomp, higher priority is more urgent, and lower ttc is better
        elsif x[1]["completed"] == nil and y[1]["completed"] == nil
           x_points = x[1]["priority"] + 1.0/x[1]["ttc"]
           y_points = y[1]["priority"] + 1.0/y[1]["ttc"]
           # Sort high to low
           y_points <=> x_points
        # For completed, just sort by date completed.
        else
           y[1]["completed"] <=> x[1]["completed"]
        end
    end
end

## Print jobs to screen
def list_jobs(all_jobs, list = nil)
    if list == "--help"
        puts "queu.rb list [current|completed|all]"
        exit
    end

    # Set the default list to print
    list = "current" if list == nil
    # Print the list of jobs
    sort_jobs(all_jobs).each do |a|
        print_job a if list == "all"
        print_job a if list == "completed" and a[1]["completed"] != nil
        print_job a if list == "current"   and a[1]["completed"] == nil
    end
end

## Insert a job into the queu.
# Either take the job info from options, or probe the user.
def add_job(all_jobs, name = nil, summary = nil, priority = nil, ttc = nil)
    # Check if we need to print help
    if name == "--help"
        puts "queu.rb add NAME SUMMARY PRIORITY TTC"
        exit
    end

    # Get the date; I'm not using this yet, but maybe soon.
    date = get_time

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
    all_jobs[name] = {"summary" => summary, "added" => date,
                         "priority" => priority.to_i, "ttc" => ttc.to_i }
    # Write the list
    write_jobs all_jobs
end

## Remove a job from the queu
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

## Mark a job as completed or uncompleted
def mark_job(all_jobs, name, status)
    if name == "--help" or name == nil
        puts "queu.rb mark NAME [completed]"
        exit
    end

    # Store the date of completion
    all_jobs[name]["completed"] = get_time

    # Write the list
    write_jobs all_jobs
end

## Pick a job from the queu
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

## Write jobs to file
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
    list_jobs all_jobs, ARGV[1]
when "pick"
    pick_job all_jobs, ARGV[1]
when "mark"
    mark_job all_jobs, ARGV[1], ARGV[2]
else
    puts "queu.rb [add|del|mark|list|pick] [OPTIONS]"
end
