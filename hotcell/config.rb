# frozen_string_literal: true

# Loaded when the cell boots, before any operation. deadline and queue_wait are seconds; memory and
# file_size are bytes. On a small host, lower concurrency and memory together (/docs/developer/hot-cell).
HotCell.limits concurrency: 4, queue_size: 8, deadline: 60, memory: 1536 * 1024**2
