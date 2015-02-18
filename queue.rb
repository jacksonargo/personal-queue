#!/usr/bin/ruby -w

require 'yaml'

## Functions

## Calculate the urgency of a job
def job_urgency(job)
    # Start with the user set priority
    points = job[1]["priority"]
    # Add in time to completion. Lower is better.
    points += 30.0/job[1]["ttc"]
    # Calculate the age multiplier
    age_rate = 1.0/(11 - job[1]["priority"])
    # Add in the priority due to age. Older is better.
    points += age_rate * (Time.now - job[1]["added"])/60/60/24
    return points
end

## Print out a job entry
def print_job(job)
    printf "Name: %s\n", job[0]
    printf "    Summary:   %s\n", job[1]["summary"]
    printf "    Priority:  %i\n", job[1]["priority"]
    printf "    TTC:       %i min\n", job[1]["ttc"]
    printf "    Added:     %s\n", job[1]["added"].to_s
    if job[1]["completed"] != nil
        printf "    Completed: %s\n", job[1]["completed"].to_s
    end
    puts
end

## Sort all jobs by priority decreasing.
# Higher priority meanis more urgent.
# Lower time to completion (ttc) is more urgent.
# The older the job is the more urgent it becomes.
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
            job_urgency(y) <=> job_urgency(x)
        # For completed, just sort by date completed.
        else
           y[1]["completed"] <=> x[1]["completed"]
        end
    end
end

## Print jobs to screen
def list_jobs(all_jobs, list = nil)
    if list == "--help"
        puts "queue.rb list [current|completed|all]"
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

## Insert a job into the queue.
# Either take the job info from options, or probe the user.
def add_job(all_jobs, name = nil, summary = nil, priority = nil, ttc = nil)
    # Check if we need to print help
    if name == "--help"
        puts "queue.rb add NAME SUMMARY PRIORITY TTC"
        exit
    end

    # Now we'll prompt the user for any info not passed as an argument.
    while name == nil
        printf "Name: "
        name = STDIN.gets.chomp
    end
    
    while summary == nil
        printf "Summary: "
        summary = STDIN.gets.chomp
    end
    
    priority = priority.to_i
    while priority < 1 or priority > 10
        printf "Priority (1-10): "
        priority = STDIN.gets.chomp.to_i
    end

    ttc = ttc.to_i
    while ttc < 1
        printf "Estimated Time (>=1min): "
        ttc = STDIN.gets.chomp.to_i
    end

    # If the job already exists, don't change it's date
    if all_jobs[name] != nil
        added = all_jobs[name]["added"]
    else
        added = Time.now
    end

    # Add the job to the list
    all_jobs[name] = {"summary" => summary, "added" => added,
                         "priority" => priority, "ttc" => ttc }
    # Write the list
    write_jobs all_jobs
end

## Remove a job from the queue
def del_job(all_jobs, name=nil)
    # Check if we need to print help
    if name == "--help"
        puts "queue.rb del NAME"
        exit
    end

    # Check if a name was provided
    while name == nil
        printf "Name of job to remove: "
        name = STDIN.gets.chomp
    end
    all_jobs.delete name

    # Write the list
    write_jobs all_jobs
end

## Mark a job as completed or uncompleted
def mark_job(all_jobs, name, status)
    if name == "--help"
        puts "queue.rb mark NAME [completed|uncompleted]"
        exit
    end

    name = '' if all_jobs[name] == nil
    while all_jobs[name] == nil
        printf "Name of job to update: "
        name = STDIN.gets.chomp
    end

    # Store the date of completion by default
    all_jobs[name]["completed"] = Time.now if status != "uncompleted"

    # Remove the date of completion if uncompleted
    all_jobs[name]["completed"] = nil      if status == "uncompleted"

    # Write the list
    write_jobs all_jobs
end

## Pick a job from the queue
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
    when "urgent"
        # Choose a random job from the 5 highed priority
        x = 5 < sorted.length ? 5 : sorted.length
        print_job sorted[rand(x)]
    when "random"
        # Choose a completely random job
        print_job sorted[rand(sorted.length)]
    else 
        puts "queue.rb pick [TOP|HIGH|RAND]"
        exit
    end
end

## Modify a job in the queue
def mod_job(all_jobs, name, attribute, value)

    # Check to make sure the job already exists
    name = '' if name == nil
    while all_jobs[name] == nil
        printf "Job name: "
        name = STDIN.gets.chomp
        printf "%s is not valid.\n", name
    end
    # Reference the job to motify with modded
    modded = all_jobs[name]
    # Check the attribute exists
    attribute = '' if attribute == nil
    while modded[attribute] == nil
        printf "Attribute: "
        attribute = STDIN.gets.chomp.downcase
        printf "%s is not valid\n", attribute
    end
    # Modify the job
    modded[attribute] = value
    # Re-add it to make sure the modifications are sane.
    add_job all_jobs, name, modded["summary"], modded["priority"],
        modded["ttc"]
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
$jobs_file=ENV['HOME']+'/.queue_jobs.yaml'

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

# Default to show current jobs
ARGV[0] = "list" if ARGV[0] == nil

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
when "mod"
    mod_job all_jobs, ARGV[1], ARGV[2], ARGV[3]
else
    puts "queue.rb [add|del|mod|mark|list|pick] [OPTIONS]..."
end
