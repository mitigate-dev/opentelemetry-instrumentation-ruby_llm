# frozen_string_literal: true

module OpenTelemetry
  module Instrumentation
    module RubyLLM
      # Converts `RubyLLM` messages and content into the JSON shape defined by
      # the GenAI semantic conventions for input/output messages and system
      # instructions:
      #
      #   https://github.com/open-telemetry/semantic-conventions-genai/blob/main/docs/gen-ai/gen-ai-input-messages.json
      #   https://github.com/open-telemetry/semantic-conventions-genai/blob/main/docs/gen-ai/gen-ai-output-messages.json
      #   https://github.com/open-telemetry/semantic-conventions-genai/blob/main/docs/gen-ai/gen-ai-system-instructions.json
      #
      # Kept separate from the `RubyLLM::Chat` patch so the formatting logic
      # does not pollute the patched class.
      module MessageFormatter
        def self.format_input_messages(messages)
          messages.map { |m| format_message(m) }.to_json
        end

        def self.format_output_messages(messages)
          messages.map { |m| format_message(m) }.to_json
        end

        def self.format_system_instructions(messages)
          messages.flat_map { |m| format_content(m.content) }.to_json
        end

        private_class_method def self.format_message(message)
          msg = { role: message.role.to_s, parts: [] }

          if message.content
            msg[:parts].concat(format_content(message.content))
          end

          if message.tool_calls&.any?
            message.tool_calls.each_value do |tc|
              msg[:parts] << { type: "tool_call", id: tc.id, name: tc.name, arguments: tc.arguments }
            end
          end

          msg[:tool_call_id] = message.tool_call_id if message.tool_call_id

          msg
        end

        # Maps a `RubyLLM::Content`/`RubyLLM::Content::Raw` onto an array of
        # GenAI message parts.
        private_class_method def self.format_content(content)
          # `RubyLLM::Content::Raw` was added in ruby_llm 1.9.0, so guard the
          # constant rather than referencing it in a `case`/`when`.
          if defined?(::RubyLLM::Content::Raw) && content.is_a?(::RubyLLM::Content::Raw)
            # Serialize the provider-specific payload to JSON so consumers
            # (e.g. Langfuse) render it as readable text rather than
            # `[object Object]`.
            [{ type: "raw", content: content.value.to_json }]
          elsif content.is_a?(::RubyLLM::Content)
            parts = []
            parts << { type: "text", content: content.text } unless content.text.nil?
            content.attachments.each do |attachment|
              parts << format_attachment(attachment)
            end
            parts
          else
            [{ type: "text", content: content.to_s }]
          end
        end

        # Maps a `RubyLLM::Attachment` onto a GenAI message part.
        private_class_method def self.format_attachment(attachment)
          part = { modality: attachment_modality(attachment) }
          part[:mime_type] = attachment.mime_type if attachment.mime_type

          if attachment.url?
            part[:type] = "uri"
            part[:uri] = attachment.source.to_s
          else
            part[:type] = "blob"
            part[:content] = attachment.source.to_s
          end

          part
        end

        # Maps a `RubyLLM::Attachment#type` onto a GenAI modality.
        private_class_method def self.attachment_modality(attachment)
          case attachment.type
          when :image then "image"
          when :video then "video"
          when :audio then "audio"
          else "document"
          end
        end
      end
    end
  end
end
