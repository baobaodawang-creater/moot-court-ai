name: evidence-round
args:
  - plaintiff_complaint
  - defendant_defense

steps:
  - id: plaintiff_evidence
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent plaintiff
      --args-json '{
        "prompt": "现在进入当前轮次的原告举证。请从工作区 evidence/ 目录中选择尚未出示的证据，说明：证据名称、证据类型（书证/物证/电子数据等）、证明目的。如果没有更多证据，明确表示举证完毕。",
        "schema": {
          "type": "object",
          "properties": {
            "evidence_name": {"type": "string"},
            "evidence_type": {"type": "string"},
            "proof_purpose": {"type": "string"},
            "evidence_content_summary": {"type": "string"},
            "no_more_evidence": {"type": "boolean"}
          },
          "required": ["no_more_evidence"]
        }
      }'

  - id: defendant_cross_exam
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent defendant
      --args-json '{
        "prompt": "原告出示了以下证据。请严格按照三性（真实性、合法性、关联性）逐一质证。如果证据有漏洞，毫不留情地指出。",
        "input": {"plaintiff_evidence": "$plaintiff_evidence.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "authenticity_challenge": {"type": "string"},
            "legality_challenge": {"type": "string"},
            "relevance_challenge": {"type": "string"},
            "overall_opinion": {"type": "string", "enum": ["认可", "部分认可", "不认可"]},
            "reasoning": {"type": "string"}
          },
          "required": ["authenticity_challenge", "legality_challenge", "relevance_challenge", "overall_opinion"]
        }
      }'
    stdin: $plaintiff_evidence.stdout

  - id: defendant_evidence
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent defendant
      --args-json '{
        "prompt": "轮到被告举证。请从工作区 evidence/ 中选择尚未出示的反证。如果没有更多证据，明确表示举证完毕。",
        "schema": {
          "type": "object",
          "properties": {
            "evidence_name": {"type": "string"},
            "evidence_type": {"type": "string"},
            "proof_purpose": {"type": "string"},
            "evidence_content_summary": {"type": "string"},
            "no_more_evidence": {"type": "boolean"}
          },
          "required": ["no_more_evidence"]
        }
      }'

  - id: plaintiff_cross_exam
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent plaintiff
      --args-json '{
        "prompt": "被告出示了以下证据。请进行质证，重点关注该证据能否有效反驳你的主张。",
        "input": {"defendant_evidence": "$defendant_evidence.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "authenticity_challenge": {"type": "string"},
            "legality_challenge": {"type": "string"},
            "relevance_challenge": {"type": "string"},
            "overall_opinion": {"type": "string", "enum": ["认可", "部分认可", "不认可"]},
            "reasoning": {"type": "string"},
            "no_more_evidence": {"type": "boolean"}
          },
          "required": ["overall_opinion", "no_more_evidence"]
        }
      }'
    stdin: $defendant_evidence.stdout
