require 'minitest/autorun'
require 'tmpdir'
require_relative 'job_queue'

class TestJobQueue < Minitest::Test
  def setup
    @queue = JobQueue.new
  end

  def make_job(name, priority: 5, ttc: 30, summary: "test", parent: nil, added: nil)
    @queue.add_job(name, summary: summary, priority: priority, ttc: ttc, parent: parent)
    @queue.jobs[name]["added"] = added if added
    @queue.jobs[name]
  end

  # --- Initialization ---

  def test_new_queue_is_empty
    assert_equal({}, @queue.jobs)
  end

  # --- add_job ---

  def test_add_job_basic
    @queue.add_job("task1", summary: "Do something", priority: 5, ttc: 30)

    assert_equal "Do something", @queue.jobs["task1"]["summary"]
    assert_equal 5, @queue.jobs["task1"]["priority"]
    assert_equal 30, @queue.jobs["task1"]["ttc"]
    assert_instance_of Time, @queue.jobs["task1"]["added"]
    assert_nil @queue.jobs["task1"]["completed"]
  end

  def test_add_job_preserves_added_date_on_update
    @queue.add_job("task1", summary: "v1", priority: 3, ttc: 10)
    original_added = @queue.jobs["task1"]["added"]

    @queue.add_job("task1", summary: "v2", priority: 7, ttc: 20)

    assert_equal original_added, @queue.jobs["task1"]["added"]
    assert_equal "v2", @queue.jobs["task1"]["summary"]
    assert_equal 7, @queue.jobs["task1"]["priority"]
  end

  def test_add_job_validates_priority
    assert_raises(ArgumentError) { @queue.add_job("x", summary: "x", priority: 0, ttc: 10) }
    assert_raises(ArgumentError) { @queue.add_job("x", summary: "x", priority: 11, ttc: 10) }
  end

  def test_add_job_validates_ttc
    assert_raises(ArgumentError) { @queue.add_job("x", summary: "x", priority: 5, ttc: 0) }
  end

  def test_add_job_validates_name
    assert_raises(ArgumentError) { @queue.add_job("", summary: "x", priority: 5, ttc: 10) }
    assert_raises(ArgumentError) { @queue.add_job(nil, summary: "x", priority: 5, ttc: 10) }
  end

  # --- delete_job ---

  def test_delete_job
    make_job("task1")
    @queue.delete_job("task1")

    assert_nil @queue.jobs["task1"]
  end

  def test_delete_nonexistent_job_raises
    assert_raises(ArgumentError) { @queue.delete_job("nope") }
  end

  def test_delete_parent_cleans_child_references
    make_job("parent")
    make_job("child", parent: "parent")

    @queue.delete_job("parent")

    assert_nil @queue.jobs["child"]["parent"]
  end

  # --- job_urgency ---

  def test_higher_priority_means_higher_urgency
    make_job("low", priority: 2, ttc: 30)
    make_job("high", priority: 8, ttc: 30)

    assert_operator @queue.job_urgency("high"), :>, @queue.job_urgency("low")
  end

  def test_lower_ttc_means_higher_urgency
    make_job("slow", priority: 5, ttc: 120)
    make_job("fast", priority: 5, ttc: 5)

    assert_operator @queue.job_urgency("fast"), :>, @queue.job_urgency("slow")
  end

  def test_older_job_has_higher_urgency
    make_job("old", priority: 5, ttc: 30, added: Time.now - 86400 * 30)
    make_job("new", priority: 5, ttc: 30, added: Time.now)

    assert_operator @queue.job_urgency("old"), :>, @queue.job_urgency("new")
  end

  def test_urgency_uses_unhold_date_when_set
    make_job("task1", priority: 5, ttc: 30)
    @queue.jobs["task1"]["added"] = Time.now - 86400 * 100
    @queue.jobs["task1"]["unhold"] = Time.now

    # With unhold set to now, age contribution should be near zero
    urgency = @queue.job_urgency("task1")
    # Compare to expected: priority(5) + 30/ttc(1.0) + age(~0) ≈ 6
    assert_in_delta 6.0, urgency, 0.5
  end

  # --- sort_jobs ---

  def test_sort_puts_incomplete_before_completed
    make_job("done", priority: 10, ttc: 1)
    @queue.mark_complete("done")
    make_job("todo", priority: 1, ttc: 120)

    sorted = @queue.sort_jobs
    assert_equal "todo", sorted[0][0]
    assert_equal "done", sorted[1][0]
  end

  def test_sort_by_urgency
    make_job("low", priority: 1, ttc: 120)
    make_job("high", priority: 10, ttc: 1)

    sorted = @queue.sort_jobs
    assert_equal "high", sorted[0][0]
    assert_equal "low", sorted[1][0]
  end

  # --- ancestor? ---

  def test_ancestor_direct_parent
    make_job("parent")
    make_job("child", parent: "parent")

    assert @queue.ancestor?("child", "parent")
    refute @queue.ancestor?("parent", "child")
  end

  def test_ancestor_grandparent
    make_job("grandparent")
    make_job("parent", parent: "grandparent")
    make_job("child", parent: "parent")

    assert @queue.ancestor?("child", "grandparent")
  end

  def test_ancestor_unrelated
    make_job("a")
    make_job("b")

    refute @queue.ancestor?("a", "b")
  end

  # --- update_dependencies! ---

  def test_update_dependencies_builds_children_array
    make_job("parent")
    make_job("child", parent: "parent")

    assert_includes @queue.jobs["parent"]["children"], "child"
  end

  def test_update_dependencies_clears_orphaned_parent
    make_job("child")
    @queue.jobs["child"]["parent"] = "nonexistent"

    @queue.update_dependencies!

    assert_nil @queue.jobs["child"]["parent"]
  end

  def test_update_dependencies_detects_cycle
    make_job("a")
    make_job("b")
    @queue.jobs["a"]["parent"] = "b"
    @queue.jobs["b"]["parent"] = "a"

    assert_raises(JobQueue::DependencyCycleError) { @queue.update_dependencies! }
  end

  # --- list_jobs ---

  def test_list_current_excludes_completed
    make_job("active")
    make_job("done")
    @queue.mark_complete("done")

    result = @queue.list_jobs("current")
    names = result.map(&:first)

    assert_includes names, "active"
    refute_includes names, "done"
  end

  def test_list_completed_only_shows_completed
    make_job("active")
    make_job("done")
    @queue.mark_complete("done")

    result = @queue.list_jobs("completed")
    names = result.map(&:first)

    refute_includes names, "active"
    assert_includes names, "done"
  end

  def test_list_held_only_shows_held
    make_job("active")
    make_job("held_job")
    @queue.hold_job("held_job")

    result = @queue.list_jobs("held")
    names = result.map(&:first)

    refute_includes names, "active"
    assert_includes names, "held_job"
  end

  def test_list_scheduled_only_shows_future
    make_job("active")
    make_job("future")
    @queue.schedule_job("future", year: 2099)

    result = @queue.list_jobs("scheduled")
    names = result.map(&:first)

    refute_includes names, "active"
    assert_includes names, "future"
  end

  def test_list_all_shows_everything
    make_job("active")
    make_job("done")
    @queue.mark_complete("done")

    result = @queue.list_jobs("all")
    names = result.map(&:first)

    assert_includes names, "active"
    assert_includes names, "done"
  end

  def test_list_reverse
    make_job("low", priority: 1, ttc: 120)
    make_job("high", priority: 10, ttc: 1)

    normal = @queue.list_jobs("current")
    reversed = @queue.list_jobs("current", reverse: true)

    assert_equal normal.map(&:first).reverse, reversed.map(&:first)
  end

  # --- hold / unhold ---

  def test_hold_job
    make_job("task1")
    @queue.hold_job("task1")

    assert_instance_of Time, @queue.jobs["task1"]["hold"]
    assert_nil @queue.jobs["task1"]["unhold"]
  end

  def test_unhold_job
    make_job("task1")
    @queue.hold_job("task1")
    @queue.unhold_job("task1")

    assert_instance_of Time, @queue.jobs["task1"]["unhold"]
  end

  def test_hold_nonexistent_raises
    assert_raises(ArgumentError) { @queue.hold_job("nope") }
  end

  # --- mark_complete / mark_incomplete ---

  def test_mark_complete
    make_job("task1")
    @queue.mark_complete("task1")

    assert_instance_of Time, @queue.jobs["task1"]["completed"]
  end

  def test_mark_complete_cascades_to_children
    make_job("parent")
    make_job("child", parent: "parent")

    marked = @queue.mark_complete("parent")

    assert_includes marked, "parent"
    assert_includes marked, "child"
    assert_instance_of Time, @queue.jobs["child"]["completed"]
  end

  def test_mark_complete_no_cascade
    make_job("parent")
    make_job("child", parent: "parent")

    @queue.mark_complete("parent", cascade: false)

    assert_instance_of Time, @queue.jobs["parent"]["completed"]
    assert_nil @queue.jobs["child"]["completed"]
  end

  def test_mark_incomplete
    make_job("task1")
    @queue.mark_complete("task1")
    @queue.mark_incomplete("task1")

    assert_nil @queue.jobs["task1"]["completed"]
  end

  def test_mark_incomplete_cascades_to_parents
    make_job("parent")
    make_job("child", parent: "parent")
    @queue.mark_complete("parent")

    marked = @queue.mark_incomplete("child")

    assert_includes marked, "child"
    assert_includes marked, "parent"
    assert_nil @queue.jobs["parent"]["completed"]
  end

  def test_mark_nonexistent_raises
    assert_raises(ArgumentError) { @queue.mark_complete("nope") }
    assert_raises(ArgumentError) { @queue.mark_incomplete("nope") }
  end

  # --- pick_job ---

  def test_pick_top
    make_job("low", priority: 1, ttc: 120)
    make_job("high", priority: 10, ttc: 1)

    result = @queue.pick_job("top")
    assert_equal "high", result[0]
  end

  def test_pick_from_empty_queue
    assert_nil @queue.pick_job("top")
  end

  def test_pick_invalid_algorithm
    make_job("task1")
    assert_raises(ArgumentError) { @queue.pick_job("invalid") }
  end

  def test_pick_urgent_returns_from_top_5
    10.times { |i| make_job("task#{i}", priority: 10 - i, ttc: 30) }

    100.times do
      result = @queue.pick_job("urgent")
      sorted = @queue.sort_jobs
      top_5_names = sorted[0..4].map(&:first)
      assert_includes top_5_names, result[0]
    end
  end

  # --- modify_job ---

  def test_modify_job
    make_job("task1", priority: 3)
    @queue.modify_job("task1", "priority", 8)

    assert_equal 8, @queue.jobs["task1"]["priority"]
  end

  def test_modify_nonexistent_raises
    assert_raises(ArgumentError) { @queue.modify_job("nope", "priority", 5) }
  end

  def test_modify_invalid_attribute_raises
    make_job("task1")
    assert_raises(ArgumentError) { @queue.modify_job("task1", "nonexistent", 5) }
  end

  # --- schedule_job ---

  def test_schedule_job
    make_job("task1")
    @queue.schedule_job("task1", year: 2099, month: 6, day: 15, hour: 10, minute: 30)

    assert_equal Time.new(2099, 6, 15, 10, 30), @queue.jobs["task1"]["schedule"]
  end

  def test_schedule_defaults_to_current_time_components
    make_job("task1")
    now = Time.now
    @queue.schedule_job("task1", year: 2099)

    sched = @queue.jobs["task1"]["schedule"]
    assert_equal 2099, sched.year
    assert_equal now.month, sched.month
  end

  def test_schedule_nonexistent_raises
    assert_raises(ArgumentError) { @queue.schedule_job("nope") }
  end

  # --- File I/O ---

  def test_save_and_load
    Dir.mktmpdir do |dir|
      path = File.join(dir, "test_jobs.yaml")

      @queue.add_job("task1", summary: "Test save", priority: 5, ttc: 30)
      @queue.save_to_file(path)

      loaded = JobQueue.load_from_file(path)

      assert_equal "Test save", loaded.jobs["task1"]["summary"]
      assert_equal 5, loaded.jobs["task1"]["priority"]
      assert_equal 30, loaded.jobs["task1"]["ttc"]
    end
  end

  def test_load_empty_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, "empty.yaml")
      File.write(path, "")

      loaded = JobQueue.load_from_file(path)
      assert_equal({}, loaded.jobs)
    end
  end

  # --- max_parent_urgency ---

  def test_max_parent_urgency_uses_highest_in_chain
    make_job("grandparent", priority: 10, ttc: 1)
    make_job("parent", priority: 1, ttc: 120, parent: "grandparent")
    make_job("child", priority: 1, ttc: 120, parent: "parent")

    child_urgency = @queue.job_urgency("child")
    max_urgency = @queue.max_parent_urgency("child")
    grandparent_urgency = @queue.job_urgency("grandparent")

    assert_operator max_urgency, :>=, child_urgency
    assert_in_delta grandparent_urgency, max_urgency, 0.001
  end
end
