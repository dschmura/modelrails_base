module LifecycleHelper
  # Sole legal display path for lifecycle state. Never render
  # `record.status.to_s` (titleized or otherwise) — that would leak the
  # internal words "Suspended"/"Discarded" into UI the vocabulary rule
  # reserves for "Locked"/"Deleted".
  def lifecycle_status_label(record)
    t("lifecycle_status.#{record.status}")
  end
end
