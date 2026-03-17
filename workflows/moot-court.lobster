name: moot-court
args:
  - case_id
  - case_brief_path

steps:
  # ══════════════════════════════════════
  # Phase 1: 开庭与诉辩交换
  # ══════════════════════════════════════

  - id: clerk_opening
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent clerk
      --args-json '{
        "prompt": "你是书记员。请宣布开庭，核对当事人，宣布法庭纪律，然后请原告陈述诉讼请求。请优先参考你工作区中的 case-brief.md；若该文件缺失，使用通用模板保守开场，不要编造新事实。严格使用书记员标准口令。",
        "schema": {
          "type": "object",
          "properties": {
            "opening_statement": {"type": "string"},
            "phase": {"type": "string"}
          },
          "required": ["opening_statement", "phase"]
        }
      }'

  - id: plaintiff_complaint
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent plaintiff
      --args-json '{
        "prompt": "你是原告代理律师。书记员已宣布开庭（附后）。请宣读起诉状，陈述诉讼请求、事实与理由。参考你工作区中的 complaint.md。每个论点必须引用具体法条。",
        "input": {"clerk_statement": "$clerk_opening.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "claims": {"type": "array", "items": {"type": "string"}},
            "facts_and_reasons": {"type": "string"},
            "legal_basis": {"type": "array", "items": {"type": "string"}}
          },
          "required": ["claims", "facts_and_reasons", "legal_basis"]
        }
      }'
    stdin: $clerk_opening.stdout

  - id: defendant_defense
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent defendant
      --args-json '{
        "prompt": "你是被告代理律师。原告已陈述诉讼请求和事实理由（附后）。请宣读答辩状，逐一回应。参考你工作区中的 defense.md。特别注意审查程序性问题：诉讼时效、管辖权、主体资格。",
        "input": {"plaintiff_complaint": "$plaintiff_complaint.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "defense_points": {"type": "array", "items": {"type": "string"}},
            "procedural_objections": {"type": "array", "items": {"type": "string"}},
            "legal_basis": {"type": "array", "items": {"type": "string"}}
          },
          "required": ["defense_points"]
        }
      }'
    stdin: $plaintiff_complaint.stdout

  # ══════════════════════════════════════
  # Phase 2: 举证质证（循环 N 轮）
  # ══════════════════════════════════════

  - id: clerk_evidence_phase
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent clerk
      --args-json '{
        "prompt": "宣布进入举证质证环节。首先由原告方举证。",
        "schema": {
          "type": "object",
          "properties": {"announcement": {"type": "string"}},
          "required": ["announcement"]
        }
      }'

  - id: evidence_rounds
    lobster: evidence-round.lobster
    args:
      plaintiff_complaint: $plaintiff_complaint.stdout
      defendant_defense: $defendant_defense.stdout
    loop:
      max_iterations: 3
      condition: >
        echo "$LOBSTER_LOOP_JSON" | python3 -c "
        import json,sys
        def parse_json_like(value):
          if isinstance(value, dict):
            return value
          if isinstance(value, str):
            try:
              return json.loads(value)
            except Exception:
              return {}
          return {}

        data = json.load(sys.stdin)
        round_data = parse_json_like(data)

        pe = parse_json_like(round_data.get('plaintiff_evidence', {}))
        de = parse_json_like(round_data.get('defendant_evidence', {}))
        px = parse_json_like(round_data.get('plaintiff_cross_exam', {}))
        plaintiff_done = bool(pe.get('no_more_evidence')) or bool(px.get('no_more_evidence'))
        defendant_done = bool(de.get('no_more_evidence'))
        global_done = bool(round_data.get('no_more_evidence'))

        stop = global_done or (plaintiff_done and defendant_done)
        sys.exit(1 if stop else 0)
        "

  # ══════════════════════════════════════
  # Phase 3: 法庭辩论
  # ══════════════════════════════════════

  - id: judge_focus_issues
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent judge
      --args-json '{
        "prompt": "你是审判长。举证质证已结束。请根据全部庭审记录归纳本案争议焦点（2-4个）。这是庭审最关键的步骤。格式：根据双方诉辩意见和举证质证情况，本庭归纳本案争议焦点如下：……",
        "input": {
          "plaintiff_complaint": "$plaintiff_complaint.stdout",
          "defendant_defense": "$defendant_defense.stdout",
          "evidence_record": "$evidence_rounds.stdout"
        },
        "schema": {
          "type": "object",
          "properties": {
            "focus_issues": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "issue_number": {"type": "integer"},
                  "description": {"type": "string"},
                  "plaintiff_position": {"type": "string"},
                  "defendant_position": {"type": "string"}
                }
              }
            },
            "announcement": {"type": "string"}
          },
          "required": ["focus_issues", "announcement"]
        }
      }'
    approval: required

  - id: plaintiff_debate
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent plaintiff
      --args-json '{
        "prompt": "审判长已归纳争议焦点（附后）。请围绕每一个争议焦点进行有力辩论。每个论点引用具体法条和已质证的证据。",
        "input": {"focus_issues": "$judge_focus_issues.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "arguments": {"type": "array", "items": {"type": "object", "properties": {"issue": {"type": "string"}, "argument": {"type": "string"}, "legal_basis": {"type": "string"}}}}
          },
          "required": ["arguments"]
        }
      }'
    stdin: $judge_focus_issues.stdout

  - id: defendant_debate
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent defendant
      --args-json '{
        "prompt": "审判长已归纳争议焦点，原告已辩论（均附后）。请针对每个焦点进行反驳和防御性论证。",
        "input": {
          "focus_issues": "$judge_focus_issues.stdout",
          "plaintiff_arguments": "$plaintiff_debate.stdout"
        },
        "schema": {
          "type": "object",
          "properties": {
            "rebuttals": {"type": "array", "items": {"type": "object", "properties": {"issue": {"type": "string"}, "rebuttal": {"type": "string"}, "legal_basis": {"type": "string"}}}}
          },
          "required": ["rebuttals"]
        }
      }'
    stdin: $plaintiff_debate.stdout

  # ══════════════════════════════════════
  # Phase 4: 最后陈述与宣判
  # ══════════════════════════════════════

  - id: plaintiff_final
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent plaintiff
      --args-json '{
        "prompt": "法庭辩论已结束。请进行最后陈述，简明总结全部诉讼请求和核心理由。",
        "schema": {
          "type": "object",
          "properties": {"final_statement": {"type": "string"}},
          "required": ["final_statement"]
        }
      }'

  - id: defendant_final
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent defendant
      --args-json '{
        "prompt": "法庭辩论已结束。请进行最后陈述，简明总结全部抗辩理由。",
        "schema": {
          "type": "object",
          "properties": {"final_statement": {"type": "string"}},
          "required": ["final_statement"]
        }
      }'

  - id: judge_verdict
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent judge
      --args-json '{
        "prompt": "庭审结束。请根据全部庭审记录，使用法律三段论，出具《模拟民事判决书》和《诉讼风险推演报告》。必须引用具体法条。判决书使用标准格式。风险报告需包含：胜诉概率、风险点、上诉理由分析、和解建议。",
        "input": {
          "plaintiff_complaint": "$plaintiff_complaint.stdout",
          "defendant_defense": "$defendant_defense.stdout",
          "evidence_record": "$evidence_rounds.stdout",
          "focus_issues": "$judge_focus_issues.stdout",
          "plaintiff_debate": "$plaintiff_debate.stdout",
          "defendant_debate": "$defendant_debate.stdout",
          "plaintiff_final": "$plaintiff_final.stdout",
          "defendant_final": "$defendant_final.stdout"
        },
        "schema": {
          "type": "object",
          "properties": {
            "judgment": {"type": "string"},
            "risk_report": {"type": "string"},
            "win_probability_plaintiff": {"type": "number"},
            "key_risks": {"type": "array", "items": {"type": "string"}},
            "settlement_suggestion": {"type": "string"}
          },
          "required": ["judgment", "risk_report", "win_probability_plaintiff"]
        }
      }'
    approval: required

  - id: clerk_closing
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent clerk
      --args-json '{
        "prompt": "宣布休庭。",
        "schema": {
          "type": "object",
          "properties": {"closing": {"type": "string"}},
          "required": ["closing"]
        }
      }'
