name: moot-court
args:
  - case_id
  - case_brief_path

steps:
  # Phase 1: 庭前准备
  - id: clerk_opening
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent clerk
      --args-json '{
        "prompt": "你是书记员。请宣布开庭，说明案由，并宣布法庭纪律。请保持庄重、简洁。",
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"}
          },
          "required": ["statement"]
        }
      }'

  - id: clerk_identity_check
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent clerk
      --args-json '{
        "prompt": "继续庭前准备。请在上一段开庭发言基础上，完成原告、被告身份核对与到庭情况确认。",
        "input": {"previous_agent_output": "$clerk_opening.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"}
          },
          "required": ["statement"]
        }
      }'
    stdin: $clerk_opening.stdout

  - id: clerk_rights_notice
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent clerk
      --args-json '{
        "prompt": "请在上一段身份核对之后，告知当事人诉讼权利义务，并宣布进入诉辩交换阶段。",
        "input": {"previous_agent_output": "$clerk_identity_check.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"}
          },
          "required": ["statement"]
        }
      }'
    stdin: $clerk_identity_check.stdout

  # Phase 2: 诉辩交换
  - id: clerk_phase2_announce
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent clerk
      --args-json '{
        "prompt": "请宣布：现在进入诉辩交换阶段，先由原告陈述诉讼请求和事实理由。",
        "input": {"previous_agent_output": "$clerk_rights_notice.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"}
          },
          "required": ["statement"]
        }
      }'
    stdin: $clerk_rights_notice.stdout

  - id: plaintiff_claims
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent plaintiff
      --args-json '{
        "prompt": "你是原告代理律师。请根据上一段书记员发言，陈述诉讼请求、事实与理由。每个核心论点必须附法律依据。",
        "input": {"previous_agent_output": "$clerk_phase2_announce.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"},
            "legal_basis": {"type": "array", "items": {"type": "string"}}
          },
          "required": ["statement", "legal_basis"]
        }
      }'
    stdin: $clerk_phase2_announce.stdout

  - id: defendant_defense
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent defendant
      --args-json '{
        "prompt": "你是被告代理律师。请基于原告发言逐项答辩，优先攻击其借款关系成立与实际交付证明链。",
        "input": {"previous_agent_output": "$plaintiff_claims.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"},
            "legal_basis": {"type": "array", "items": {"type": "string"}}
          },
          "required": ["statement", "legal_basis"]
        }
      }'
    stdin: $plaintiff_claims.stdout

  # Phase 3: 举证质证（第1轮）
  - id: clerk_phase3_announce
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent clerk
      --args-json '{
        "prompt": "请宣布：现在进入举证质证第一轮，先由原告举证。",
        "input": {"previous_agent_output": "$defendant_defense.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"}
          },
          "required": ["statement"]
        }
      }'
    stdin: $defendant_defense.stdout

  - id: plaintiff_evidence_round1
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent plaintiff
      --args-json '{
        "prompt": "你是原告代理律师。请在第一轮举证中提交关键证据，必须同时说明借款合意证据和实际交付证据。",
        "input": {"previous_agent_output": "$clerk_phase3_announce.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"},
            "evidence_list": {"type": "array", "items": {"type": "string"}}
          },
          "required": ["statement", "evidence_list"]
        }
      }'
    stdin: $clerk_phase3_announce.stdout

  - id: defendant_cross_round1
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent defendant
      --args-json '{
        "prompt": "你是被告代理律师。请对原告第一轮证据进行三性质证（真实性、合法性、关联性），重点攻击实际交付证明不足。",
        "input": {"previous_agent_output": "$plaintiff_evidence_round1.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"},
            "three_nature_challenges": {"type": "array", "items": {"type": "string"}}
          },
          "required": ["statement", "three_nature_challenges"]
        }
      }'
    stdin: $plaintiff_evidence_round1.stdout

  - id: judge_question_round1
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent judge
      --args-json '{
        "prompt": "你是审判长。请针对第一轮举证质证结果提出审查性问题，重点围绕借款是否实际交付。",
        "input": {"previous_agent_output": "$defendant_cross_round1.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"}
          },
          "required": ["statement"]
        }
      }'
    stdin: $defendant_cross_round1.stdout

  # Phase 4: 举证质证（第2轮）
  - id: clerk_phase4_announce
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent clerk
      --args-json '{
        "prompt": "请宣布：现在进入举证质证第二轮，由被告举证，原告随后质证。",
        "input": {"previous_agent_output": "$judge_question_round1.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"}
          },
          "required": ["statement"]
        }
      }'
    stdin: $judge_question_round1.stdout

  - id: defendant_evidence_round2
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent defendant
      --args-json '{
        "prompt": "你是被告代理律师。请在第二轮提交反证，重点说明为何原告不能证明借款实际交付。",
        "input": {"previous_agent_output": "$clerk_phase4_announce.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"},
            "evidence_list": {"type": "array", "items": {"type": "string"}}
          },
          "required": ["statement", "evidence_list"]
        }
      }'
    stdin: $clerk_phase4_announce.stdout

  - id: plaintiff_cross_round2
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent plaintiff
      --args-json '{
        "prompt": "你是原告代理律师。请对被告第二轮证据进行三性质证并反驳其结论。",
        "input": {"previous_agent_output": "$defendant_evidence_round2.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"},
            "three_nature_challenges": {"type": "array", "items": {"type": "string"}}
          },
          "required": ["statement", "three_nature_challenges"]
        }
      }'
    stdin: $defendant_evidence_round2.stdout

  - id: judge_question_round2
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent judge
      --args-json '{
        "prompt": "你是审判长。请针对第二轮争点继续发问，并明确引导双方围绕借款实际交付进行说明。",
        "input": {"previous_agent_output": "$plaintiff_cross_round2.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"}
          },
          "required": ["statement"]
        }
      }'
    stdin: $plaintiff_cross_round2.stdout

  # Phase 5: 法庭辩论
  - id: clerk_phase5_announce
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent clerk
      --args-json '{
        "prompt": "请宣布：举证质证结束，现在进入法庭辩论阶段。",
        "input": {"previous_agent_output": "$judge_question_round2.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"}
          },
          "required": ["statement"]
        }
      }'
    stdin: $judge_question_round2.stdout

  - id: judge_focus_issues
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent judge
      --args-json '{
        "prompt": "你是审判长。请归纳本案争议焦点（2-4项），并明确双方围绕焦点辩论。",
        "input": {"previous_agent_output": "$clerk_phase5_announce.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"},
            "focus_issues": {"type": "array", "items": {"type": "string"}}
          },
          "required": ["statement", "focus_issues"]
        }
      }'
    stdin: $clerk_phase5_announce.stdout
    approval: required

  - id: plaintiff_debate
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent plaintiff
      --args-json '{
        "prompt": "你是原告代理律师。请围绕审判长归纳的争议焦点进行辩论，每个焦点都要给出法律依据。",
        "input": {"previous_agent_output": "$judge_focus_issues.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"},
            "legal_basis": {"type": "array", "items": {"type": "string"}}
          },
          "required": ["statement", "legal_basis"]
        }
      }'
    stdin: $judge_focus_issues.stdout

  - id: defendant_debate
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent defendant
      --args-json '{
        "prompt": "你是被告代理律师。请围绕同一争议焦点进行反驳，强调原告举证不足与证明标准未达成。",
        "input": {"previous_agent_output": "$plaintiff_debate.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"},
            "legal_basis": {"type": "array", "items": {"type": "string"}}
          },
          "required": ["statement", "legal_basis"]
        }
      }'
    stdin: $plaintiff_debate.stdout

  # Phase 6: 最后陈述
  - id: clerk_phase6_announce
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent clerk
      --args-json '{
        "prompt": "请宣布：法庭辩论结束，现在进入最后陈述阶段，先由原告后由被告陈述。",
        "input": {"previous_agent_output": "$defendant_debate.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"}
          },
          "required": ["statement"]
        }
      }'
    stdin: $defendant_debate.stdout

  - id: plaintiff_final_statement
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent plaintiff
      --args-json '{
        "prompt": "你是原告代理律师。请作最后陈述，简明总结请求、事实与法律依据。",
        "input": {"previous_agent_output": "$clerk_phase6_announce.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"}
          },
          "required": ["statement"]
        }
      }'
    stdin: $clerk_phase6_announce.stdout

  - id: defendant_final_statement
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent defendant
      --args-json '{
        "prompt": "你是被告代理律师。请作最后陈述，简明总结抗辩主张与法律依据。",
        "input": {"previous_agent_output": "$plaintiff_final_statement.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"}
          },
          "required": ["statement"]
        }
      }'
    stdin: $plaintiff_final_statement.stdout

  # Phase 7: 宣判
  - id: clerk_phase7_announce
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent clerk
      --args-json '{
        "prompt": "请宣布：最后陈述结束，现在进入宣判阶段，请审判长宣读判决。",
        "input": {"previous_agent_output": "$defendant_final_statement.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"}
          },
          "required": ["statement"]
        }
      }'
    stdin: $defendant_final_statement.stdout

  - id: judge_verdict
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent judge
      --args-json '{
        "prompt": "你是审判长。请基于全案事实与举证质证情况，按法律三段论宣读判决。民间借贷争议必须审查借款实际交付（民法典第679条）。",
        "input": {"previous_agent_output": "$clerk_phase7_announce.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "judgment": {"type": "string"},
            "reasoning": {"type": "string"}
          },
          "required": ["judgment", "reasoning"]
        }
      }'
    stdin: $clerk_phase7_announce.stdout
    approval: required

  - id: clerk_closing
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent clerk
      --args-json '{
        "prompt": "请宣布庭审结束并闭庭。",
        "input": {"previous_agent_output": "$judge_verdict.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "statement": {"type": "string"}
          },
          "required": ["statement"]
        }
      }'
    stdin: $judge_verdict.stdout
