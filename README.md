Personal Queue
=============

#### Table of Contents
1. [Synopsis](#synopsis)
2. [Description](#desctiption)
3. [Operations](#operations)
    * [add](#add)
    * [del](#del)
    * [mod](#mod)
    * [mark](#mark)
    * [list](#list)
    * [mod](#mod)
    * [hold](#hold)
    * [unhold](#unhold)
    * [schedule](#schedule)
    * 
4. [Sorting](#sorting)
5. [Bugs](#bugs)
6. [Authors](#authors)

## Synopsis
    queue.rb [SUBCOMMAND] [OPTION]...
    queue.rb add [NAME] [SUMMARY] [PRIORITY] [TIME TO COMPLETION]
    queue.rb del [NAME]
    queue.rb mod [NAME] [ATTRIBUTE] [VALUE]
    queue.rb mark [NAME] [completed]
    queue.rb list [current|completed|held|scheduled|all]
    queue.rb hold NAME [release]
    queue.rb unhold NAME
    queue.rb schedule NAME [YEAR] [MONTH] [DAY] [HOUR] [MINUTE]

## Description

This is a ruby script to maintain a personal queue of jobs that you don't want 
to forget to complete. The jobs are sorted by priority, estimated time
required, and how long the job has been in the queue. The jobs are stored in the
yaml file ~/.queue\_jobs.yaml.

## Operations

### add

Adds a job to the queue. Job description can be given as parameters or 
interactively.

* *NAME* is a descriptive name for the job.
* *SUMMARY* is a brief summary of the what you have to do. This should be given
as a single string.
* *PRIORITY* is an integer 1-10. Higher priority means the job needs to be
completed sooner.
* *TIME TO COMPLETION*, or TTC, is an estimate in minutes of how long you think it will
take to finish this job. Jobs with lower TTC will be sorted before jobs
with higher TTC.

### del

Deletes the job NAME from the queue. NAME can be given as a parameter or
interactively.

* *NAME* is the name of the job to delete.

### mod

Modifies the description of a job. Currently you can only modify one
attribute at a time. The NAME, ATTRIBUTE, and VALUE can be given as
parameters or interactively.

* *NAME* is the name of the job to modify.
* *ATTRIBUTE* can be one of name, summary, priority, ttc, added, or
completed.
* *VALUE* is the new description of that attribute.

### mark

Marks NAME as completed or uncompleted. If no STATUS is given, then
the job will be marked as completed. If NAME is not given, it will
be asked for interactively.

* *NAME* is the name of the job.
* *STATUS* can be either completed or uncompleted. Uncompleted jobs are sorted
apart from completed jobs.

### list

Lists the jobs in the queue. If no other argument is given, queue.rb will
sort and list only the uncompleted jobs. To list only the completed
jobs use 'queue.rb list completed', and to list all jobs use
'queue.rb list all'.

### hold

Puts the job NAME on hold and keeps it from being listed with the current jobs.
If "release" is given after NAME, the job will no longer be on hold. Released
jobs printed in the current job list, but sorted by the date they were released
rather than the date they were added.

### unhold

Removes a hold on the job NAME. Equivalent to 'queue.rb hold NAME release'.

### schedule

This lets you schedule when a job should start or should have started. Jobs scheduled
to start in the future are not listed with the current jobs, but can be seen with
'queue.rb list scheduled'. Scheduled jobs are sorted by the date they are scheduled to
start and not by the date added. Scheduling a job in the past allows you to retain the date
added but also give the job a higher priority due to age.
The job NAME must be added before a schedule can be added.
YEAR, MONTH, DAY, HOUR, and MINUTE are optional and will be replaced with the current
system date and time if ommitted.

## Sorting

Jobs are sorted by combining priority, time to completion (TTC), and age.
Jobs with higher priority and lower TTC are usually sorted above jobs with
lower priority and higher TTC. The longer a job is left uncompleted, the
more "urgent" it becomes and it will be sorted above other jobs. If left
neglected long enough, a job of priority 1 can be sorted above a job of
priority 10. Jobs with higher priority will gain urgency faster than jobs
with lower priority.
Once a job is marked as completed, it is sorted with other
completed jobs by the time of completion.
Uncompleted jobs are sorted by the following formula:

    PRIORITY + 30/TTC + DAYS OLD/(11-PRIORITY)

## Examples

    queue.rb add "queue.rb-README.md" "Write the README.md file for queue.rb" 7 30
    queue.rb mark "queue.rb-README.md"

## Bugs
If you find any bugs or want to recommend features, send an email to
ignition.argo@gmail.com

## Authors
* Jackson Argo

Queue.rb                            2015-03-09                         README.md
