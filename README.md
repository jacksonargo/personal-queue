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
    * [pick](#pick)
4. [Sorting](#sorting)
5. [Bugs](#bugs)
6. [Authors](#authors)

## Synopsis
    queue.rb [SUBCOMMAND] [OPTION]...
    queue.rb add [NAME] [SUMMARY] [PRIORITY] [TIME TO COMPLETION]
    queue.rb del [NAME]
    queue.rb mod [NAME] [ATTRIBUTE] [VALUE]
    queue.rb mark [NAME] [STATUS]
    queue.rb list [current|completed|all]
    queue.rb pick [top|high|rand]

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
take to finish this job. Jobs with lower TTC will have precedence over jobs
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
then the job will be marked as completed. If NAME is not given, it will
be asked for interactively.

* *NAME* is the name of the job.
* *STATUS* can be either completed or uncompleted. Uncompleted jobs are sorted
apart from completed jobs.

### list

Lists the jobs in the que. If no other argument is given, queue.rb will
sort and list only the uncompleted jobs. To list only the completed
jobs use 'queue.rb list completed', and to list all jobs use
'queue.rb list all'.

### pick

Prints only one job from the que. If no other argument is given, then
the most urgent job is printed. To pick a random but urgent job use
'queue.rb pick urgent', and to pick a completely random job use
'queue.rb pick random'.

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

Queue.rb                            2015-02-17                         README.md
