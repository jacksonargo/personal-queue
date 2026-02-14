require 'yaml'

# JobQueue encapsulates all business logic for managing a prioritized task queue.
# It operates on an in-memory hash and never does file I/O, STDIN reads, or exits,
# making it fully testable in isolation.
class JobQueue
  attr_reader :jobs

  def initialize(jobs = {})
    @jobs = jobs
  end

  def self.load_from_file(path)
    data = YAML.safe_load(File.read(path), permitted_classes: [Time])
    new(data.is_a?(Hash) ? data : {})
  end

  def save_to_file(path)
    File.write(path, @jobs.to_yaml)
  end

  # Calculate the urgency score for a job.
  # Higher score = more urgent.
  def job_urgency(name)
    job = @jobs[name]
    return 0 unless job

    points = job["priority"]
    points += 30.0 / job["ttc"]

    age_rate = 1.0 / (11 - job["priority"])

    if job["unhold"]
      points += age_rate * (Time.now - job["unhold"]) / 60 / 60 / 24
    elsif job["schedule"]
      points += age_rate * (Time.now - job["schedule"]) / 60 / 60 / 24
    else
      points += age_rate * (Time.now - job["added"]) / 60 / 60 / 24
    end

    points
  end

  # Check if `parent` is an ancestor of `child` in the dependency chain.
  def ancestor?(child, parent)
    current = child
    while current
      return true if @jobs[current]["parent"] == parent
      current = @jobs[current]["parent"]
    end
    false
  end

  # Find the maximum urgency in a job's parent chain (including itself).
  def max_parent_urgency(name)
    max = job_urgency(name)
    current = name
    loop do
      current = @jobs[current]["parent"]
      break unless current
      cur = job_urgency(current)
      max = cur if cur > max
    end
    max
  end

  # Sort all jobs by urgency (descending). Returns an array of [name, attrs] pairs.
  def sort_jobs
    @jobs.sort do |x, y|
      if x[1]["completed"].nil? && !y[1]["completed"].nil?
        -1
      elsif !x[1]["completed"].nil? && y[1]["completed"].nil?
        1
      elsif ancestor?(x[0], y[0])
        -1
      elsif ancestor?(y[0], x[0])
        1
      elsif x[1]["completed"].nil? && y[1]["completed"].nil?
        max_parent_urgency(y[0]) <=> max_parent_urgency(x[0])
      else
        y[1]["completed"] <=> x[1]["completed"]
      end
    end
  end

  # Update parent/child relationships, fixing stale references.
  # Raises if a dependency cycle is detected.
  def update_dependencies!
    # Rebuild children arrays from parent references
    @jobs.each_key do |name|
      parent = @jobs[name]["parent"]
      next unless parent

      if @jobs[parent].nil?
        @jobs[name]["parent"] = nil
        next
      end

      @jobs[parent]["children"] ||= []
      @jobs[parent]["children"] << name
    end

    # Clean up children arrays
    @jobs.each_key do |name|
      next unless @jobs[name]["children"]

      @jobs[name]["children"].uniq!

      @jobs[name]["children"].reject! do |child|
        @jobs[child].nil? || @jobs[child]["parent"] != name
      end

      @jobs[name]["children"] = nil if @jobs[name]["children"].empty?
    end

    # Check for dependency cycles
    @jobs.each_key do |name|
      current = @jobs[name]["parent"]
      while current
        if current == name
          raise DependencyCycleError,
            "Dependency cycle detected: #{name} -> ... -> #{current} -> ... -> #{name}"
        end
        current = @jobs[current]["parent"]
      end
    end
  end

  # Filter and sort jobs by status. Returns array of [name, attrs] pairs.
  def list_jobs(filter = "current", reverse: false)
    sorted = sort_jobs
    sorted = sorted.reverse if reverse

    sorted.select do |_name, attrs|
      case filter
      when "all"
        true
      when "completed"
        !attrs["completed"].nil?
      when "held"
        !attrs["hold"].nil? && attrs["unhold"].nil?
      when "scheduled"
        attrs["schedule"] && attrs["schedule"] > Time.now
      else # "current"
        attrs["completed"].nil? &&
          (attrs["hold"].nil? || !attrs["unhold"].nil?) &&
          (attrs["schedule"].nil? || attrs["schedule"] <= Time.now)
      end
    end
  end

  # Add or update a job. Returns the job hash.
  def add_job(name, summary:, priority:, ttc:, parent: nil)
    raise ArgumentError, "Name is required" if name.nil? || name.empty?
    raise ArgumentError, "Priority must be between 1 and 10" unless (1..10).include?(priority)
    raise ArgumentError, "TTC must be >= 1" unless ttc >= 1

    added = @jobs.dig(name, "added") || Time.now

    @jobs[name] = {
      "summary" => summary,
      "added" => added,
      "priority" => priority,
      "ttc" => ttc,
      "parent" => parent
    }

    update_dependencies! if parent
    @jobs[name]
  end

  # Remove a job from the queue.
  def delete_job(name)
    raise ArgumentError, "Job '#{name}' does not exist" unless @jobs[name]

    has_deps = !@jobs[name]["parent"].nil? || !@jobs[name]["children"].nil?
    @jobs.delete(name)
    update_dependencies! if has_deps
  end

  # Put a job on hold.
  def hold_job(name)
    raise ArgumentError, "Job '#{name}' does not exist" unless @jobs[name]

    @jobs[name]["hold"] = Time.now
    @jobs[name]["unhold"] = nil
  end

  # Release a job from hold.
  def unhold_job(name)
    raise ArgumentError, "Job '#{name}' does not exist" unless @jobs[name]

    @jobs[name]["unhold"] = Time.now
  end

  # Mark a job as completed, optionally cascading to children.
  # Returns the list of job names that were marked.
  def mark_complete(name, cascade: true)
    raise ArgumentError, "Job '#{name}' does not exist" unless @jobs[name]

    marked = [name]
    @jobs[name]["completed"] = Time.now

    if cascade && @jobs[name]["children"]
      @jobs[name]["children"].each do |child|
        marked.concat(mark_complete(child, cascade: true))
      end
    end

    marked
  end

  # Mark a job as incomplete, optionally cascading to parents.
  # Returns the list of job names that were marked.
  def mark_incomplete(name, cascade: true)
    raise ArgumentError, "Job '#{name}' does not exist" unless @jobs[name]

    marked = [name]
    @jobs[name]["completed"] = nil

    if cascade && @jobs[name]["parent"]
      marked.concat(mark_incomplete(@jobs[name]["parent"], cascade: true))
    end

    marked
  end

  # Pick a job using the given algorithm. Returns a [name, attrs] pair.
  def pick_job(algorithm = "top")
    sorted = sort_jobs
    return nil if sorted.empty?

    case algorithm
    when "top"
      sorted[0]
    when "urgent"
      count = [5, sorted.length].min
      sorted[rand(count)]
    when "random"
      sorted[rand(sorted.length)]
    else
      raise ArgumentError, "Unknown algorithm '#{algorithm}'. Use top, urgent, or random."
    end
  end

  # Modify a specific attribute of a job.
  def modify_job(name, attribute, value)
    raise ArgumentError, "Job '#{name}' does not exist" unless @jobs[name]
    raise ArgumentError, "Attribute '#{attribute}' does not exist" unless @jobs[name].key?(attribute)

    @jobs[name][attribute] = value

    if ["priority", "ttc", "summary"].include?(attribute)
      add_job(name,
        summary: @jobs[name]["summary"],
        priority: @jobs[name]["priority"],
        ttc: @jobs[name]["ttc"],
        parent: @jobs[name]["parent"])
    end
  end

  # Schedule a job for a future date.
  def schedule_job(name, year: nil, month: nil, day: nil, hour: nil, minute: nil)
    raise ArgumentError, "Job '#{name}' does not exist" unless @jobs[name]

    now = Time.now
    @jobs[name]["schedule"] = Time.new(
      year || now.year,
      month || now.month,
      day || now.day,
      hour || now.hour,
      minute || now.min
    )
  end

  class DependencyCycleError < StandardError; end
end
