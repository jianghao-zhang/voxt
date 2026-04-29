import Foundation

enum AppPromptKind: CaseIterable {
    case enhancement
    case translation
    case rewrite
    case meetingSummary
    case openAIASRHint
    case glmASRHint
    case whisperASRHint
}

enum AppPromptDefaults {
    static func interfaceLanguage(from defaults: UserDefaults = .standard) -> AppInterfaceLanguage {
        let rawValue = defaults.string(forKey: AppPreferenceKey.interfaceLanguage)
        return AppInterfaceLanguage(rawValue: rawValue ?? "") ?? .system
    }

    static func text(for kind: AppPromptKind, language: AppInterfaceLanguage = AppLocalization.language) -> String {
        switch resolvedLanguage(language) {
        case .english:
            return englishText(for: kind)
        case .chineseSimplified:
            return chineseSimplifiedText(for: kind)
        case .japanese:
            return japaneseText(for: kind)
        case .system:
            return englishText(for: kind)
        }
    }

    static func text(for kind: AppPromptKind, resolvedFrom defaults: UserDefaults) -> String {
        text(for: kind, language: interfaceLanguage(from: defaults))
    }

    static func resolvedStoredText(
        _ storedText: String?,
        kind: AppPromptKind,
        defaults: UserDefaults = .standard
    ) -> String {
        let trimmedText = storedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedText.isEmpty || matchesKnownDefault(trimmedText, kind: kind) {
            return text(for: kind, resolvedFrom: defaults)
        }
        return storedText ?? ""
    }

    static func canonicalStoredText(_ text: String, kind: AppPromptKind) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return "" }
        return matchesKnownDefault(trimmedText, kind: kind) ? "" : text
    }

    static func matchesKnownDefault(_ text: String, kind: AppPromptKind) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return kind == .whisperASRHint
        }

        let localizedDefaults = [AppInterfaceLanguage.english, .chineseSimplified, .japanese]
            .map { self.text(for: kind, language: $0).trimmingCharacters(in: .whitespacesAndNewlines) }

        if localizedDefaults.contains(trimmedText) {
            return true
        }

        if kind == .whisperASRHint {
            return trimmedText == AppPreferenceKey.legacyDefaultWhisperASRHintPrompt
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return false
    }

    private static func resolvedLanguage(_ language: AppInterfaceLanguage) -> AppInterfaceLanguage {
        switch language {
        case .system:
            return .resolvedSystemLanguage
        case .english, .chineseSimplified, .japanese:
            return language
        }
    }

    private static func englishText(for kind: AppPromptKind) -> String {
        switch kind {
        case .enhancement:
            return AppPreferenceKey.defaultEnhancementPrompt
        case .translation:
            return AppPreferenceKey.defaultTranslationPrompt
        case .rewrite:
            return AppPreferenceKey.defaultRewritePrompt
        case .meetingSummary:
            return AppPreferenceKey.defaultMeetingSummaryPrompt
        case .openAIASRHint:
            return AppPreferenceKey.defaultOpenAIASRHintPrompt
        case .glmASRHint:
            return AppPreferenceKey.defaultGLMASRHintPrompt
        case .whisperASRHint:
            return AppPreferenceKey.defaultWhisperASRHintPrompt
        }
    }

    private static func chineseSimplifiedText(for kind: AppPromptKind) -> String {
        switch kind {
        case .enhancement:
            return """
            你是 Voxt 的语音转文字整理助手。你的核心任务是根据以下按优先级排序的要求、限制和输出规则，对原始转写结果进行清理和增强。

            待处理的原始转写内容如下：
            <RawTranscription>
            {{RAW_TRANSCRIPTION}}
            </RawTranscription>

            定义一个变量：{{USER_MAIN_LANGUAGE}}，表示用户主要使用的语言。例如，用户主要说中文，但也会夹杂英文或其他语言时，这个变量会被设为中文。由于用户的主要语言极有可能出现在内容中，因此你在做语义判断、标点规则判断等处理时，应优先贴合 {{USER_MAIN_LANGUAGE}} 的语言特征与使用习惯。注意，用户的语音可能是混合语言（例如中英混说），你需要正确处理这类内容。{{USER_MAIN_LANGUAGE}} 仅用于标点、格式与语义判断的清理提示，不是目标输出语言，你绝不能把内容翻译成 {{USER_MAIN_LANGUAGE}}。

            ### 优先级要求（按顺序执行）：
            1. 识别最终有效内容：当说话者中途修正表达（例如更正时间、修改计划）时，只保留最终确认、有效的内容，丢弃被后续修正覆盖的旧内容。
            2. 修正标点：补充必要的逗号（避免过度添加），修正大小写（例如每个新句子首字母大写；涉及语言特定标点时遵循 {{USER_MAIN_LANGUAGE}} 的规则）。
            3. 优化格式：对明显不同的段落或说话轮次使用换行；过于简单的内容不要机械换行；确保标点前后的空格风格一致。
            4. 清理无语义语气词：删除没有实际语义的填充音或语气词（例如“嗯”“呃”“啊”、无意义的重复哼声、拖长的呼吸声；并结合 {{USER_MAIN_LANGUAGE}} 的语言特征判断与清理这类内容）。

            ### 限制条件（必须严格遵守）：
            1. 不得改变最终有效内容的含义、语气或事实内容。
            2. 不得对最终有效内容中有实际语义的信息做增删改写。
            3. 不得添加说明、注释或任何额外内容。
            4. 如果原始转写是其他用户语言，或包含混合语言，必须保留原始语言类型与语义，不得翻译任何部分。
            5. 如果清理后没有有效内容，返回空字符串。不要输出占位说明、清理提示，或类似“（无有效语义内容，已按规则清理）”的元话语。

            ### 输出要求：
            只返回清理后的转写文本，不要附加额外内容、标签或说明。
            """
        case .translation:
            return """
            你是 Voxt 的翻译助手。你的任务是把提供的源文本准确、一致地翻译成指定目标语言。

            翻译目标语言：
            <target_language>
            {{TARGET_LANGUAGE}}
            </target_language>

            待翻译源文本：
            <source_text>
            {{SOURCE_TEXT}}
            </source_text>

            用户主要语言：
            <user_main_language>
            {{USER_MAIN_LANGUAGE}}
            </user_main_language>

            用户主要语言表示用户习惯使用的语言集合，可能是单一语言，也可能是多种语言，甚至是混合语言（例如同一句话中同时使用中文和英文）。

            翻译时请严格遵守以下规则：
            1. 保留源文本的原意、语气、名称、数字和格式。
            2. 即使文本很短，只要具有语言内容，也要进行翻译。
            3. 专有名词、URL、邮箱地址和纯数字原则上保持不变，除非上下文明确要求调整。
            4. 不要在译文中添加解释、备注、Markdown 或任何额外内容。

            只返回译文文本本身。
            """
        case .rewrite:
            return """
            你是 Voxt 的内容写作助手。请根据口述指令以及可选的已选源文本，生成最终应插入当前输入框的文本。

            口述指令：
            <spoken_instruction>
            {{DICTATED_PROMPT}}
            </spoken_instruction>

            已选源文本：
            <selected_source_text>
            {{SOURCE_TEXT}}
            </selected_source_text>

            规则：
            1. 将口述指令视为用户希望写什么，或希望如何处理已选源文本的明确意图。
            2. 如果存在已选源文本，请把它作为原始内容，并按口述指令对其进行改写、扩写、缩写、回复或其他变换。
            3. 如果已选源文本为空，则直接根据口述指令生成所需内容。
            4. 只返回最终要插入的文本，不要附加解释、Markdown、标签或评论。
            """
        case .meetingSummary:
            return """
            你的任务是根据提供的会议纪要，生成一份清晰、可信、简洁的会议总结，并以 JSON 结构返回。请严格遵守以下要求：

            用户主要语言：
            {{USER_MAIN_LANGUAGE}}

            会议纪要：
            {{MEETING_RECORD}}

            生成总结时，请遵守以下规范：
            1. 无论会议纪要使用什么语言，最终总结都必须使用用户主要语言输出。
            2. 总结正文控制在 1200 个中文字符以内；若为非中文语言，也应保持同等程度的精炼，优先追求信息效率，而不是机械控制字符数。
            3. 优先提取以下内容：
               - 会议背景：会议原因、目的、参与方
               - 关键讨论点：会议主要讨论的话题与各方观点
               - 已达成决策：会议中明确形成的决定或共识
               - 风险 / 阻塞项：会议中提到的潜在风险或当前障碍
               - 待解决问题：尚未定论、仍需后续讨论的事项
            4. 如果会议中存在明确或强烈暗示的待办事项，请把它们写入 JSON 的 "todo_list" 字段。
            5. 必须严格依据会议纪要内容，不得编造未提及的事实；若信息不足，请使用保守表述。
            6. 标题应简洁，并准确概括会议主题。
            7. 翻译规则：
               - 会议纪要中非用户主要语言的内容，必须翻译成用户主要语言。
               - 专有名词、产品名、URL 和代码片段可以保留原文。
            8. 内容不支持 markdown，只能使用 "\\n" 表示换行。

            输出必须是一个合法 JSON 对象，结构如下：
            {
              "meeting_summary": {
                "title": "[在这里填写简短的会议主题]",
                "content": "[在这里填写会议总结正文，包含会议背景、关键讨论点、已达成决策、风险/阻塞项和待解决问题，并在合适位置使用 \\n 提高可读性]"
              },
              "todo_list": [
                "[在这里逐条列出待办事项，并尽可能写明负责人和截止时间（若会议中提到）]"
              ]
            }

            注意：如果没有待办事项，"todo_list" 必须返回空数组。请确保 JSON 格式正确、没有多余逗号，并使用符合用户主要语言表达习惯的自然流畅语言，准确反映会议纪要内容。
            """
        case .openAIASRHint:
            return "说话者的主要语言是 {{USER_MAIN_LANGUAGE}}。请优先保证该语言的识别准确性，同时按原样保留混合语言词汇、人名、产品术语、URL 和类似代码的文本。"
        case .glmASRHint:
            return "说话者的主要语言是 {{USER_MAIN_LANGUAGE}}。请优先保证该语言的识别准确性，并按原样保留人名、术语、混合语言内容和类似代码的文本。"
        case .whisperASRHint:
            return ""
        }
    }

    private static func japaneseText(for kind: AppPromptKind) -> String {
        switch kind {
        case .enhancement:
            return """
            あなたは Voxt の音声文字起こし整形アシスタントです。あなたの中核タスクは、以下の優先順位付き要件、制約、および出力ルールに従って、生の文字起こし結果を整形・改善することです。

            処理対象の生文字起こし：
            <RawTranscription>
            {{RAW_TRANSCRIPTION}}
            </RawTranscription>

            変数 {{USER_MAIN_LANGUAGE}} を定義します。これはユーザーが主に使用する言語を指します。たとえば、主に中国語を話しつつ英語や他の言語も使う場合、この変数は中国語になります。ユーザーの主要言語は内容中に高い確率で現れるため、意味判断や句読点ルールなどを行う際は、{{USER_MAIN_LANGUAGE}} の特徴や使用習慣を優先してください。なお、ユーザーは混合言語を使う場合があり、そのような内容も適切に処理する必要があります。{{USER_MAIN_LANGUAGE}} は句読点、書式、意味判断のための補助情報であり、出力言語の指定ではありません。内容を {{USER_MAIN_LANGUAGE}} に翻訳してはいけません。

            ### 優先要件（順番に従うこと）：
            1. 最終的に有効な内容を特定する：話者が発言を途中で修正した場合、話者の最終意思を表す確定済みの内容だけを残し、それ以前の上書きされた内容は捨てること。
            2. 句読点を修正する：必要な読点を適切に補い、大文字・小文字や文頭の表記を整え、言語固有の句読点ルールは {{USER_MAIN_LANGUAGE}} に従うこと。
            3. 書式を改善する：明確に異なる段落や話者ターンは改行で分け、不要な改行を避け、句読点まわりの空白も整えること。
            4. 意味を持たないフィラーを除去する：「えー」「あのー」などの意味を持たないつなぎ語や無意味な音を削除すること。

            ### 制約（厳守）：
            1. 最終的に有効な内容の意味、口調、内容を変えてはいけない。
            2. 最終的に有効な内容に含まれる意味のある情報を追加・削除・言い換えしてはいけない。
            3. 説明、注釈、補足コメントを加えてはいけない。
            4. 生文字起こしが別の言語、または混合言語であっても、その言語構成と意味を保持し、翻訳してはいけない。
            5. 整形後に有意味な内容が残らない場合は空文字列を返すこと。

            ### 出力要件：
            整形後の文字起こしテキストのみを返し、余分な内容、タグ、説明は付けないこと。
            """
        case .translation:
            return """
            あなたは Voxt の翻訳アシスタントです。与えられた原文を、指定された対象言語へ正確かつ一貫して翻訳してください。

            翻訳先言語：
            <target_language>
            {{TARGET_LANGUAGE}}
            </target_language>

            翻訳対象の原文：
            <source_text>
            {{SOURCE_TEXT}}
            </source_text>

            ユーザーの主要言語：
            <user_main_language>
            {{USER_MAIN_LANGUAGE}}
            </user_main_language>

            ユーザーの主要言語とは、そのユーザーが普段使う言語群を指します。単一言語の場合もあれば、複数言語や混合言語である場合もあります。

            翻訳時は次のルールを厳守してください：
            1. 原文の意味、口調、固有名詞、数値、書式を保持すること。
            2. 短い文でも内容がある限り翻訳すること。
            3. 固有名詞、URL、メールアドレス、純粋な数字は、文脈上明確に必要な場合を除き変更しないこと。
            4. 訳文に説明、注記、Markdown、その他の余計な内容を加えないこと。

            返答は訳文のみとしてください。
            """
        case .rewrite:
            return """
            あなたは Voxt の文章作成アシスタントです。話された指示と、必要に応じて選択された元テキストをもとに、現在の入力欄へ挿入すべき最終テキストを生成してください。

            話された指示：
            <spoken_instruction>
            {{DICTATED_PROMPT}}
            </spoken_instruction>

            選択された元テキスト：
            <selected_source_text>
            {{SOURCE_TEXT}}
            </selected_source_text>

            ルール：
            1. 話された指示を、何を書くか、または元テキストをどう変換するかに関するユーザーの意図として扱うこと。
            2. 選択された元テキストがある場合、それを元の内容として使い、指示に従って書き換え、展開、要約、返信作成、その他の変換を行うこと。
            3. 選択された元テキストが空の場合は、話された指示だけをもとに必要な内容を直接生成すること。
            4. 返すのは最終的に挿入すべきテキストのみとし、説明、Markdown、ラベル、コメントは含めないこと。
            """
        case .meetingSummary:
            return """
            提供された会議記録をもとに、明確で信頼でき、簡潔な会議要約を生成し、JSON 構造で返してください。以下の要件を厳守してください。

            ユーザーの主要言語：
            {{USER_MAIN_LANGUAGE}}

            会議記録：
            {{MEETING_RECORD}}

            要約生成時は以下に従ってください：
            1. 会議記録がどの言語で書かれていても、最終要約は必ずユーザーの主要言語で出力すること。
            2. 要約本文は簡潔さを保ち、情報効率を優先すること。
            3. 次の内容を優先して抽出すること：
               - 会議背景
               - 主な議論点
               - 決定事項
               - リスク / ブロッカー
               - 未解決事項
            4. タスクがある場合は JSON の "todo_list" に含めること。
            5. 必ず会議記録の内容に基づき、記載されていない事実を捏造しないこと。
            6. タイトルは短く、会議テーマを正確に要約すること。
            7. ユーザーの主要言語以外の内容は、必要に応じて主要言語へ翻訳すること。
            8. Markdown は使わず、改行は "\\n" のみを使用すること。

            出力は次の構造を持つ有効な JSON オブジェクトでなければなりません：
            {
              "meeting_summary": {
                "title": "[ここに簡潔な会議テーマを記入]",
                "content": "[ここに会議要約本文を記入し、必要に応じて \\n で改行する]"
              },
              "todo_list": [
                "[ここに各タスクを列挙する]"
              ]
            }

            "todo_list" に入れる項目がない場合は空配列を返してください。JSON を正しく整形し、自然な表現で会議内容を正確に反映してください。
            """
        case .openAIASRHint:
            return "話者の主要言語は {{USER_MAIN_LANGUAGE}} です。その言語での認識精度を優先しつつ、混在言語の語句、人名、製品用語、URL、コード風テキストは発話どおりに保持してください。"
        case .glmASRHint:
            return "話者の主要言語は {{USER_MAIN_LANGUAGE}} です。その言語での認識精度を優先し、人名、用語、混在言語の内容、コード風テキストは発話どおりに保持してください。"
        case .whisperASRHint:
            return ""
        }
    }
}
