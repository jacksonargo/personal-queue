#!/usr/bin/ruby -w

require_relative 'job_queue'
require 'fileutils'

## Formatting helpers

def print_job(entry)
  name, job = entry
  printf "Name: %s\n", name
  printf "\tSummary:   %s\n", job["summary"]
  printf "\tPriority:  %i\n", job["priority"]
  printf "\tTTC:       %i min\n", job["ttc"]
  printf "\tParent:    %s\n", job["parent"] if job["parent"]
  if job["children"]
    printf "\tChildren:\n"
    job["children"].each { |n| printf "\t\t%s\n", n }
  end
  printf "\tAdded:     %s\n", job["added"].to_s
  printf "\tStart:     %s\n", job["schedule"].to_s if job["schedule"]
  printf "\tHeld:      %s\n", job["hold"].to_s if job["hold"]
  printf "\tUnheld:    %s\n", job["unhold"].to_s if job["unhold"]
  printf "\tCompleted: %s\n", job["completed"].to_s if job["completed"]
  puts
end

## CLI commands

def cmd_list(queue, opts, list)
  if list == "--help" || opts == "--help"
    printf "Usage: %s list [-v] [current|completed|scheduled|held|all]\n", $0
    exit
  end

  if queue.jobs.empty?
    puts "No jobs to list!"
    exit
  end

  # Handle -v flag
  if list.nil? && opts != '-v'
    list = opts
    opts = nil
  end

  list ||= "current"
  reverse = opts == '-v'

  queue.list_jobs(list, reverse: reverse).each { |entry| print_job(entry) }
end

def cmd_add(queue, name, summary, priority, ttc, parent)
  if name == "--help"
    printf "Usage: %s add NAME SUMMARY PRIORITY TTC PARENT\n", $0
    exit
  end

  while name.nil? || name.empty?
    printf "Name: "
    name = STDIN.gets.chomp
  end

  while summary.nil? || summary.empty?
    printf "Summary: "
    summary = STDIN.gets.chomp
  end

  priority = priority.to_i
  while priority < 1 || priority > 10
    printf "Priority (1-10): "
    priority = STDIN.gets.chomp.to_i
  end

  ttc = ttc.to_i
  while ttc < 1
    printf "Estimated Time (>=1min): "
    ttc = STDIN.gets.chomp.to_i
  end

  queue.add_job(name, summary: summary, priority: priority, ttc: ttc, parent: parent)
  queue.save_to_file($jobs_file)
end

def cmd_del(queue, name)
  if name == "--help"
    printf "Usage: %s del NAME\n", $0
    exit
  end

  while name.nil? || name.empty?
    printf "Name of job to remove: "
    name = STDIN.gets.chomp
  end

  queue.delete_job(name)
  queue.save_to_file($jobs_file)
end

def cmd_hold(queue, name, status)
  if name == "--help"
    printf "Usage: %s hold NAME [release]\n", $0
    exit
  end

  unless queue.jobs[name]
    printf "Sorry, job %s doesn't exist.\n", name
    exit 1
  end

  if status == "release"
    queue.unhold_job(name)
  else
    queue.hold_job(name)
  end
  queue.save_to_file($jobs_file)
end

def cmd_mark(queue, name, status)
  if name == "--help"
    printf "%s mark NAME [incomplete]\n", $0
    exit
  end

  name = '' unless queue.jobs[name]
  while queue.jobs[name].nil?
    printf "Name of job to update: "
    name = STDIN.gets.chomp
  end

  if status == "incomplete"
    if queue.jobs[name]["parent"]
      printf "This will mark all parent jobs as incomplete too.\n"
      printf "Do you want to continue [Y/n]? "
      ans = STDIN.gets.chomp.downcase
      return if ans == "n"
    end
    queue.mark_incomplete(name)
  else
    if queue.jobs[name]["children"]
      printf "This will mark all child jobs as complete too.\n"
      printf "Do you want to continue [Y/n]? "
      ans = STDIN.gets.chomp.downcase
      return if ans == "n"
    end
    queue.mark_complete(name)
  end

  queue.save_to_file($jobs_file)
end

def cmd_pick(queue, algorithm)
  result = queue.pick_job(algorithm || "top")
  if result
    print_job(result)
  else
    puts "No jobs to pick from!"
  end
end

def cmd_mod(queue, name, attribute, value)
  while name.nil? || !queue.jobs[name]
    printf "Job name: "
    name = STDIN.gets.chomp
  end

  while attribute.nil? || !queue.jobs[name].key?(attribute)
    printf "Attribute: "
    attribute = STDIN.gets.chomp.downcase
  end

  queue.modify_job(name, attribute, value)
  queue.save_to_file($jobs_file)
end

def cmd_schedule(queue, name, year, month, day, hour, minute)
  if name == "--help" || name == "-h"
    printf "Usage: %s schedule NAME [YEAR] [MONTH] [DAY] [HOUR] [MINUTE]\n", $0
    printf "List date and time numerically. Anything omitted will be "
    printf "replaced with system time.\n"
    exit 0
  end

  unless queue.jobs[name]
    printf "The job %s doesn't exist. Please create it first.\n", name
    exit 1
  end

  queue.schedule_job(name,
    year: year&.to_i,
    month: month&.to_i,
    day: day&.to_i,
    hour: hour&.to_i,
    minute: minute&.to_i)
  queue.save_to_file($jobs_file)
end

##
## Main
##

$jobs_file = ENV['HOME'] + '/.queue_jobs.yaml'

unless File.exist? $jobs_file
  printf "The data file %s does not exist.\n", $jobs_file
  printf "Would you like to create it [Y/n]? "
  ans = STDIN.gets.chomp
  if ans != 'n' && ans != 'no'
    FileUtils.touch($jobs_file)
  end
end

queue = if File.exist?($jobs_file) && !File.zero?($jobs_file)
  JobQueue.load_from_file($jobs_file)
else
  if File.exist?($jobs_file)
    puts "Initializing empty data file."
    q = JobQueue.new
    q.save_to_file($jobs_file)
    q
  else
    JobQueue.new
  end
end

ARGV[0] = "list" if ARGV[0].nil?

case ARGV[0]
when "add"
  cmd_add queue, ARGV[1], ARGV[2], ARGV[3], ARGV[4], ARGV[5]
when "del"
  cmd_del queue, ARGV[1]
when "list"
  cmd_list queue, ARGV[1], ARGV[2]
when "-v"
  cmd_list queue, "-v", nil
when "pick"
  cmd_pick queue, ARGV[1]
when "mark"
  cmd_mark queue, ARGV[1], ARGV[2]
when "mod"
  cmd_mod queue, ARGV[1], ARGV[2], ARGV[3]
when "hold"
  cmd_hold queue, ARGV[1], ARGV[2]
when "unhold"
  cmd_hold queue, ARGV[1], "release"
when "schedule"
  cmd_schedule queue, ARGV[1], ARGV[2], ARGV[3], ARGV[4], ARGV[5], ARGV[6]
else
  printf "%s [add|del|mod|mark|list|pick|hold|unhold|schedule] [OPTIONS]...\n", $0
end
