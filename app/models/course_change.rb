class CourseChange < ApplicationRecord
  belongs_to :course
  belongs_to :exchange
  belongs_to :undo_of, class_name: "CourseChange", optional: true
  has_many_attached :retained_covers
  has_many :assistant_activities, dependent: :nullify
  has_many :draft_cover_requests, dependent: :nullify
  has_many :undo_changes, class_name: "CourseChange", foreign_key: :undo_of_id, dependent: :nullify

  def self.record!(course:, exchange:, operation:, undo_of: nil)
    before_state = Drafts::Snapshot.capture(course)
    change = new(course: course, exchange: exchange, operation: operation, undo_of: undo_of,
      revision: course.revision + 1, before_state: before_state)
    if before_state["cover_blob_id"]
      change.retained_covers.attach(ActiveStorage::Blob.find(before_state["cover_blob_id"]))
    end
    result = yield
    course.increment(:revision).save!
    change.after_state = Drafts::Snapshot.capture(course)
    if change.after_state["cover_blob_id"] && change.after_state["cover_blob_id"] != before_state["cover_blob_id"]
      change.retained_covers.attach(ActiveStorage::Blob.find(change.after_state["cover_blob_id"]))
    end
    change.save!
    [ change, result ]
  end

  def self.latest_undoable(course)
    return unless where(course: course).maximum(:revision) == course.revision
    candidate = where(course: course, undo_of_id: nil, undone_at: nil).order(revision: :desc).first
    candidate if candidate && candidate.after_state == Drafts::Snapshot.capture(course)
  end

  def undo!(expected_revision:, actor: exchange, allow_active_actor: false)
    Drafts::Access.synchronize(course) do
      Drafts::Access.ensure_available!(course, exchange: allow_active_actor ? actor : nil, allow_plan: true)
      unless course.revision == expected_revision && self.class.latest_undoable(course)&.id == id
        raise Drafts::Error.new("revision_conflict", "Later changes must be reviewed before undoing this change.")
      end
      change, = self.class.record!(course: course, exchange: actor, operation: "undo_change", undo_of: self) do
        Drafts::Snapshot.restore!(course, before_state)
        update!(undone_at: Time.current)
      end
      change
    end
  end
end
