#!/usr/bin/ruby -w

require 'yaml'

## Functions

## Write jobs to file
def write_jobs (all_jobs)
    f = File.open($jobs_file, "w")
    f.write all_jobs.to_yaml
    f.close
end

## Calculate the urgency of a job
def job_urgency(job)
    # Start with the user set priority
    points = job["priority"]
    # Add in time to completion. Lower is better.
    points += 30.0/job["ttc"]
    # Calculate the age multiplier
    age_rate = 1.0/(11 - job["priority"])
    # Add in the priority due to age. Older is better.
    # If the job was held, then we use the unhold date.
    # If the job has been scheduled, we use that date.
    if job["unhold"] != nil
        points += age_rate * (Time.now - job["unhold"])/60/60/24
    elsif job["schedule"] != nil
        points += age_rate * (Time.now - job["schedule"])/60/60/24
    else
        points += age_rate * (Time.now - job["added"])/60/60/24
    end
    return points
end

## Print out a job entry
def print_job(job)
    printf "Name: %s\n", job[0]
    printf "\tSummary:   %s\n", job[1]["summary"]
    printf "\tPriority:  %i\n", job[1]["priority"]
    printf "\tTTC:       %i min\n", job[1]["ttc"]
    if job[1]["parent"] != nil
        printf "\tParent:    %s\n", job[1]["parent"]
    end
    if job[1]["children"] != nil
        printf "\tChildren:\n"
        job[1]["children"].each do |n|
            printf "\t\t%s\n", n
        end
    end
    printf "\tAdded:     %s\n", job[1]["added"].to_s
    if job[1]["schedule"] != nil
        printf "\tStart:     %s\n", job[1]["schedule"].to_s
    end
    if job[1]["hold"] != nil
        printf "\tHeld:      %s\n", job[1]["hold"].to_s
    end
    if job[1]["unhold"] != nil
        printf "\tUnheld:    %s\n", job[1]["unhold"].to_s
    end
    if job[1]["completed"] != nil
        printf "\tCompleted: %s\n", job[1]["completed"].to_s
    end
    puts
end

## Check if a job is parent of another job
def check_if_parent(all_jobs, child, parent)
    #return false if child == nil or parent == nil
    while child != nil
        return true if all_jobs[child]["parent"] == parent
        child = all_jobs[child["parent"]]
    end
    return false
end

## Find the parent's greatest urgency points
def get_parent_urgency(all_jobs, child)
    max = job_urgency(all_jobs[child])
    loop do
        child = all_jobs[child]["parent"]
        break if child == nil
        cur = job_urgency(all_jobs[child])
        max = max > cur ? max : cur
    end
    return max
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
        # Check if one job is the parent of the other.
        elsif check_if_parent all_jobs, x[0], y[0]
            -1
        elsif check_if_parent all_jobs, y[0], x[0]
            1
        # For uncomp, higher priority is more urgent, and lower ttc is better
        elsif x[1]["completed"] == nil and y[1]["completed"] == nil
            get_parent_urgency(all_jobs, y[0]) <=> get_parent_urgency(all_jobs, x[0])
        # For completed, just sort by date completed.
        else
           y[1]["completed"] <=> x[1]["completed"]
        end
    end
end

## Update all the job parent/child relationships
def update_job_dependencies(all_jobs)
    # First we'll check that each parent node knows the children
    all_jobs.each_key do |m|
        parent = all_jobs[m]["parent"]
        # Check if this job has a parent
        next if parent == nil
        # Check if the parent job exists
        if all_jobs[parent] == nil
            all_jobs[m]["parent"] = nil
            next
        end
        # Check that the parent has a children array
        if all_jobs[parent]["children"] == nil
            all_jobs[parent]["children"] = []
        end
        # Add the job to the array
        all_jobs[parent]["children"] << m
    end
    # Now we'll check that each parent's children are still it's children
    all_jobs.each_key do |m|
        # Check that the job has children
        next if all_jobs[m]["children"] == nil
        # Remove any dupes
        all_jobs[m]["children"].uniq!
        # Delete any children who don't have this job as a parent
        all_jobs[m]["children"].each do |k|
            # Check if the child exists
            if all_jobs[k] == nil
                all_jobs[m]["children"].delete(k)
            # Check if the child recognizes this parent
            elsif all_jobs[k]["parent"] != m
                all_jobs[m]["children"].delete(k)
            end
        end
        # Check if there children left
        all_jobs[m]["children"] = nil if all_jobs[m]["children"] == []
    end
    # Now we have to check for dependency cycles
    all_jobs.each_key do |m|
        start = m
        current = m["parent"]
        while current != nil
            if current == start
                puts "Not updating job list because a dependency cycle has been found."
                printf "%s -> ... -> %s -> ... -> %s\n", start, current, start
                exit 1
            end
            current = all_jobs[current["parent"]]
        end
    end
    # Finally we are done
    return all_jobs
end

## Print jobs to screen
def list_jobs(all_jobs, opts = nil, list = nil)
    if list == "--help"
        puts "queue.rb list [-v] [current|completed|scheduled|all]"
        exit
    end

    if all_jobs == {}
        puts "No jobs to list!"
        exit
    end

    # Check for options
    if list == nil and opts != '-v'
        list = opts
        opts = nil
    end

    # Sort the jobs
    sorted = sort_jobs(all_jobs)
    sorted = sorted.reverse if opts == '-v'

    # Set the default list to print
    list = "current" if list == nil

    # Print the list of jobs
    sorted.each do |a|
        if list == "all"
            print_job a
        elsif a[1]["completed"] != nil
            print_job a if list == "completed"
        elsif a[1]["hold"] != nil and a[1]["unhold"] == nil
            print_job a if list == "held"
        elsif a[1]["schedule"] != nil and a[1]["schedule"] > Time.now
            print_job a if list == "scheduled"
        else
            print_job a if list == "current"
        end
    end
end

## Insert a job into the queue.
# Either take the job info from options, or probe the user.
def add_job(all_jobs, name = nil, summary = nil, priority = nil, ttc = nil, parent = nil)
    # Check if we need to print help
    if name == "--help"
        puts "queue.rb add NAME SUMMARY PRIORITY TTC PARENT"
        exit
    end

    ## Now we'll prompt the user for any info not passed as an argument.

    # Name
    while name == nil
        printf "Name: "
        name = STDIN.gets.chomp
    end
    
    # Summary
    while summary == nil
        printf "Summary: "
        summary = STDIN.gets.chomp
    end
    
    # Priority
    priority = priority.to_i
    while priority < 1 or priority > 10
        printf "Priority (1-10): "
        priority = STDIN.gets.chomp.to_i
    end

    # Time to Completion
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
        "priority" => priority, "ttc" => ttc, "parent" => parent }

    # Update dependencies
    all_jobs = update_job_dependencies(all_jobs) if parent != nil

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

    # Check if the job has dependencies
    if all_jobs[name]["parent"] != nil or all_jobs[name]["children"] != nil
        hasdependencies = true
    else
        hasdependencies = false
    end

    # Delete the job
    all_jobs.delete name

    # Update dependencies if we need
    all_jobs = update_job_dependencies(all_jobs) if hasdependencies

    # Write the list
    write_jobs all_jobs
end

## Put a job on hold
def hold_job(all_jobs, name, status = nil)
    if name == "--help"
        puts "queue.rb hold NAME [release]"
        exit
    end
    if all_jobs[name] == nil
        printf "Sorry, job %s doesn't exist.\n", name
        exit 1
    end
    status = "hold" if status == nil
    if status != "release"
        all_jobs[name]["hold"] = Time.now
        all_jobs[name]["unhold"] = nil
    else
        all_jobs[name]["unhold"] = Time.now
    end

    # Write the list
    write_jobs all_jobs
end


## Mark a job as completed or incomplete
def mark_job(all_jobs, name, status, query = true)
    if name == "--help"
        puts "queue.rb mark NAME [incomplete]"
        exit
    end

    name = '' if all_jobs[name] == nil
    while all_jobs[name] == nil
        printf "Name of job to update: "
        name = STDIN.gets.chomp
    end

    # By default, mark the job and children completed
    if status != "incomplete"
        # Check if this job has children
        if all_jobs[name]["children"] == nil
            all_jobs[name]["completed"] = Time.now
        # Mark all children
        else
            ans = ''
            if query
                printf "This will mark all child jobs as complete too.\n"
                printf "Do you want to continue [Y/n]? "
                ans = STDIN.gets.chomp.downcase
            else
                ans = "y"
            end
            if ans != "n"
                # Mark this job
                all_jobs[name]["completed"] = Time.now
                # Mark the children
                all_jobs[name]["children"].each do
                    |m| mark_job(all_jobs, m, status, false)
                end
            end
        end
    # Mark the job and parent and incomplete
    else
        # Mark this job
        if all_jobs[name]["parent"] == nil
            all_jobs[name]["completed"] = nil
        # Mark parents
        else
            ans = ''
            if query
                printf "This will mark all parent jobs as incomplete too.\n"
                printf "Do you want to continue [Y/n]? "
                ans = STDIN.gets.chomp.downcase
            else
                ans = "y"
            end
            if ans != "n"
                all_jobs[name]["completed"] = nil
                mark_job(all_jobs, all_jobs[name]["parent"], status, false)
            end
        end
    end

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

## Schedule a job
def schedule_job(all_jobs, name, year, month, day, hour, minute)
    # Check for help
    if name == "--help" or name == "-h"
        printf "Usage: %s date NAME [YEAR] [MONTH] [DAY] [HOUR] [MINUTE]\n", $0
        printf "List date and time numerically. Anything omitted will be "
        printf "replaced with system time.\n"
        exit 0
    end
    # Check that the job exists
    if all_jobs[name] == nil
        printf "The job %s doesn't exist. Please create it first.\n", name
        exit 1
    end
    # Set the date for the job
    year = Time.now.year if year == nil
    month = Time.now.month if month == nil
    day = Time.now.day if day == nil
    hour = Time.now.hour if hour == nil
    minute = Time.now.min if minute == nil
    all_jobs[name]["schedule"] = Time.new(year, month, day, hour, minute)
    write_jobs all_jobs
end


##
## Main
##

# This is where the job data is stored.
$jobs_file=ENV['HOME']+'/.queue_jobs.yaml'

# Check that the file exists
unless File.exist? $jobs_file
    printf "The data file %s does not exist.\n", $jobs_file
    printf "Would you like to create it [Y/n]? "
    ans = STDIN.gets.chomp
    if ans != 'n' or ans != 'no'
        require 'fileutils'
        FileUtils.touch($jobs_file)
    end
end

# Read in all the current jobs
all_jobs = YAML::load( File.open $jobs_file )

# Initialize all_jobs if the file was empty
if all_jobs == false
    puts "Initializing empty data file."
    all_jobs = {}
    write_jobs all_jobs
end

# Default to show current jobs
ARGV[0] = "list" if ARGV[0] == nil

case ARGV[0]
when "add"
    add_job all_jobs, ARGV[1], ARGV[2], ARGV[3], ARGV[4], ARGV[5]
when "del"
    del_job all_jobs, ARGV[1]
when "list"
    list_jobs all_jobs, ARGV[1], ARGV[2]
when "-v"
    list_jobs all_jobs, "-v"
when "pick"
    pick_job all_jobs, ARGV[1]
when "mark"
    mark_job all_jobs, ARGV[1], ARGV[2]
when "mod"
    mod_job all_jobs, ARGV[1], ARGV[2], ARGV[3]
when "hold"
    hold_job all_jobs, ARGV[1], ARGV[2]
when "unhold"
    hold_job all_jobs, ARGV[1], "release"
when "schedule"
    schedule_job all_jobs, ARGV[1], ARGV[2], ARGV[3], ARGV[4], ARGV[5], ARGV[6]
else
    puts "queue.rb [add|del|mod|mark|list|pick|hold|unhold|schedule] [OPTIONS]..."
end
