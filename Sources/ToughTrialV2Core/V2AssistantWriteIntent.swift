import Foundation

/// Host-side gate for assistant requests that may reach a business write.
///
/// Model output, memory, and compact summaries are deliberately absent from
/// this API. They can provide context for a request, but they cannot authorize
/// a write.
public enum V2AssistantWriteIntent {
    /// The model may prepare a reviewable proposal for an unfamiliar request.
    /// This is not permission to apply it: the host must require confirmation.
    public static func mayPrepareReview(_ text: String) -> Bool {
        let value = compactText(text)
        guard !value.isEmpty, !isStandaloneGreeting(value), !isNegated(value),
              !isReadOnlyRequest(value), !isDiscussionOrFeedback(value),
              !["引用", "原文", "举例", "例如", "假如", "如果", "quote", "example"].contains(where: value.contains) else { return false }
        return true
    }

    public static func authorize(
        _ text: String,
        priorMessages: [V2AgentMessage] = [],
        hasTaskReference: Bool = false
    ) -> Bool {
        let compact = compactText(text)
        guard !compact.isEmpty else { return false }

        if isReadOnlyRequest(compact) || isStandaloneGreeting(compact) || isNegated(compact) {
            return false
        }

        if isDiscussionOrFeedback(compact), !hasExplicitWriteClause(compact) {
            return false
        }

        if isDirectWriteRequest(compact, hasTaskReference: hasTaskReference) {
            return true
        }

        guard isClarificationReply(compact) else { return false }
        return inheritsFromAdjacentClarification(
            priorMessages,
            reply: compact,
            hasTaskReference: hasTaskReference
        )
    }

    /// Returns whether text looks like an answer to a bounded clarification.
    /// The answer is not authority by itself; `authorize` still requires the
    /// immediately preceding successful clarification and write request.
    public static func isClarificationReply(_ text: String) -> Bool {
        let compact = compactText(text)
        guard !compact.isEmpty,
              !isStandaloneGreeting(compact),
              !isNegated(compact),
              !isDiscussionOrFeedback(compact) else {
            return false
        }

        let exactReplies = [
            "是", "是的", "对", "对的", "可以", "行", "好的", "好",
            "没问题", "其他的没问题", "其他没问题", "都可以", "都行",
            "确定", "确认", "按这个", "按你说的", "按刚才的", "就这样",
            "我同意", "同意"
        ]
        if exactReplies.contains(compact) {
            return true
        }

        return compact.contains("没问题")
            || compact.contains("就今天")
            || compact.contains("就明天")
            || compact.contains("按这个")
            || compact.contains("按你说")
            || containsDateAnswer(compact)
    }
}

private extension V2AssistantWriteIntent {
    static let writeMarkers = [
        "新增", "创建", "新建", "添加", "建立", "记录", "记下", "记账", "保存", "写下", "存下", "设置", "设定",
        "修改", "更新", "编辑", "调整", "改到", "改成", "改为", "延期", "推迟", "顺延", "挪到", "换到",
        "排到", "排期", "排程", "安排", "加入今天", "加入计划", "列入日程", "放到", "移到", "取消排期", "取消安排",
        "完成", "做完", "标记完成", "打勾", "勾选",
        "归档", "存档", "封存", "恢复", "启用", "停用", "删除", "移除", "撤销", "应用", "采纳", "确认分类", "确认账单", "确认已", "已付款", "已支付", "付过", "扣款成功", "已扣费", "已经还款", "还款了", "付清", "付款", "支付",
        "create", "newtask", "addtask", "update", "edit", "reschedule", "schedule", "complete", "markdone", "archive", "restore"
    ]

    static let breakdownMarkers = ["拆分", "拆解", "分解", "分一下", "分一分", "拆一下", "拆一拆", "细分", "细化", "拆小", "拆开", "拆成", "分成", "拆为", "分为", "breakdown", "breaktask", "split"]

    static let negativeMarkers = [
        "不要", "别", "先别", "先不要", "先不", "暂时不", "暂时不要",
        "不用", "不需要", "不必", "无需", "不想", "请勿",
        "dont", "donot", "noneed"
    ]

    static func compactText(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
                && !CharacterSet.punctuationCharacters.contains($0)
        })
    }

    static func isDirectWriteRequest(_ compact: String, hasTaskReference: Bool) -> Bool {
        if breakdownMarkers.contains(where: compact.contains) {
            return hasTaskReference || hasTextualTaskReference(compact)
        }

        guard writeMarkers.contains(where: compact.contains) else { return false }
        if isReadOnlyRequest(compact) && !hasExplicitWriteClause(compact) {
            return false
        }
        if isCapabilityQuestion(compact) && !hasExplicitRequestPhrase(compact) {
            return false
        }
        return true
    }

    static func hasExplicitWriteClause(_ compact: String) -> Bool {
        guard writeMarkers.contains(where: compact.contains) else { return false }
        return writeMarkers.contains(where: compact.hasPrefix)
            || hasExplicitRequestPhrase(compact)
    }

    static func hasTextualTaskReference(_ compact: String) -> Bool {
        var remainder = compact
        let filler = [
            "能不能", "可不可以", "可以", "帮我", "帮忙", "请你", "请",
            "一下", "任务", "拆分", "拆解", "分解", "啊", "吧",
            "breakdown", "breaktask", "split", "task"
        ]
        for word in filler {
            remainder = remainder.replacingOccurrences(of: word, with: "")
        }
        return remainder.count >= 2
    }

    static func isStandaloneGreeting(_ compact: String) -> Bool {
        [
            "hello", "hi", "hey", "你好", "您好", "嗨", "哈喽", "早上好", "晚上好",
            "谢谢", "多谢", "感谢", "谢啦", "thanks", "thankyou"
        ].contains(compact)
    }

    static func isReadOnlyRequest(_ compact: String) -> Bool {
        let readOnlyPrefixes = [
            "查看", "看看", "查询", "搜索", "查找", "检索", "读取", "读一下", "显示", "列出", "浏览",
            "show", "list", "search", "query", "find"
        ]
        let politeReadOnlyPrefixes = [
            "帮我看看", "帮我查看", "帮我查询", "帮我查", "请查看", "请查询", "请搜索", "请列出"
        ]
        return readOnlyPrefixes.contains(where: compact.hasPrefix)
            || politeReadOnlyPrefixes.contains(where: compact.hasPrefix)
    }

    static func isNegated(_ compact: String) -> Bool {
        guard operationMarkers.contains(where: compact.contains) else {
            return negativeMarkers.contains(where: compact.hasPrefix)
        }

        return !hasPositiveWriteOperation(compact)
    }

    static var operationMarkers: [String] {
        writeMarkers + breakdownMarkers
    }

    static func hasPositiveWriteOperation(_ compact: String) -> Bool {
        for marker in operationMarkers {
            var searchStart = compact.startIndex
            while searchStart < compact.endIndex,
                  let range = compact.range(of: marker, range: searchStart..<compact.endIndex) {
                if !isOperationNegated(range, in: compact) {
                    return true
                }
                searchStart = range.upperBound
            }
        }
        return false
    }

    static func isOperationNegated(_ range: Range<String.Index>, in compact: String) -> Bool {
        let prefix = compact[..<range.lowerBound]
        let contextStart = operationMarkers.reduce(prefix.startIndex) { currentStart, marker in
            guard let previousOperation = prefix.range(of: marker, options: .backwards) else {
                return currentStart
            }
            return max(currentStart, previousOperation.upperBound)
        }
        let context = String(prefix[contextStart...])
        return negativeMarkers.contains(where: context.contains)
    }

    static func isDiscussionOrFeedback(_ compact: String) -> Bool {
        let leadingHypothetical = ["如果", "假如", "若", "要是", "if"].contains(where: compact.hasPrefix)
        let feedback = [
            "为什么", "怎么还", "怎么没", "怎么没有", "没进入今天", "没有进入今天", "未进入今天",
            "没有生效", "没生效", "失败", "报错", "出错", "不工作", "没反应", "发生什么",
            "是什么意思", "什么是", "解释一下", "会怎样", "会怎么样", "有什么影响", "请问", "怎么", "如何", "how", "why", "whatdoes"
        ].contains(where: compact.contains)
        return leadingHypothetical || feedback
    }

    static func hasExplicitRequestPhrase(_ compact: String) -> Bool {
        [
            "帮我", "帮忙", "麻烦", "请你", "请帮", "请把", "请将", "请创建", "请新增", "请添加",
            "能不能", "能否", "可不可以", "可否", "能不能帮", "可以帮", "可不可以帮", "可否帮", "想请你", "替我", "为我",
            "canyou", "couldyou", "please", "helpme", "iwantyouto"
        ].contains(where: compact.contains)
            || (compact.hasPrefix("请") && !compact.hasPrefix("请问"))
            || (compact.contains("请") && !compact.contains("请问"))
    }

    static func isCapabilityQuestion(_ compact: String) -> Bool {
        compact.contains("可以吗")
            || compact.contains("能不能")
            || compact.contains("可不可以")
            || compact.contains("是否")
            || compact.contains("要不要")
            || compact.hasSuffix("吗")
            || compact.hasPrefix("can")
            || compact.hasPrefix("could")
    }

    static func containsDateAnswer(_ compact: String) -> Bool {
        ["今天", "明天", "后天", "大后天", "本周", "下周", "周一", "周二", "周三", "周四", "周五", "周六", "周日", "星期"].contains(where: compact.contains)
            || compact.range(of: #"\d{1,4}年\d{1,2}月(?:\d{1,2}日)?"#, options: .regularExpression) != nil
            || compact.range(of: #"\d{1,2}[/-]\d{1,2}(?:[/-]\d{1,4})?"#, options: .regularExpression) != nil
    }

    static func inheritsFromAdjacentClarification(
        _ messages: [V2AgentMessage],
        reply: String,
        hasTaskReference: Bool
    ) -> Bool {
        guard messages.count >= 2,
              let user = messages.dropLast().last,
              let agent = messages.last,
              user.role == .user,
              user.status == .complete,
              agent.role == .agent,
              agent.status == .complete,
              !agent.parts.contains(where: { part in
                  if case .error = part { return true }
                  return false
              }),
              authorize(user.plainText, hasTaskReference: hasTaskReference),
              isSuccessfulClarification(agent.plainText) else {
            return false
        }
        if reply == "好" || reply == "好的" {
            return isExplicitWriteConfirmation(agent.plainText)
        }
        return true
    }

    static func isExplicitWriteConfirmation(_ text: String) -> Bool {
        let compact = compactText(text)
        let hasConfirmationSignal = ["确认", "是否", "要不要", "可以", "吗"].contains(where: compact.contains)
        let hasWriteOrDateTarget = writeMarkers.contains(where: compact.contains)
            || compact.contains("任务")
            || containsDateAnswer(compact)
        return hasConfirmationSignal && hasWriteOrDateTarget
    }

    static func isSuccessfulClarification(_ text: String) -> Bool {
        let compact = compactText(text)
        guard !compact.isEmpty else { return false }
        let asksQuestion = text.contains(where: { $0 == "?" || $0 == "？" })
            || compact.contains("吗")
            || compact.contains("是否")
            || compact.contains("要不要")
            || compact.contains("请确认")
            || compact.contains("请告诉")
            || compact.contains("请选择")
        let hasClarificationSignal = [
            "确认", "是否", "要不要", "请选择", "请告诉", "请补充", "请提供", "具体要", "具体是",
            "哪天", "什么时候", "哪个", "日期", "排到", "安排到", "请确定"
        ].contains(where: compact.contains)
        let asksTaskOrDate = [
            "任务", "内容", "具体", "日期", "哪天", "什么时候", "今天", "明天", "后天",
            "安排", "排到", "哪个", "标题", "几点", "周"
        ].contains(where: compact.contains)
        return asksQuestion && hasClarificationSignal && asksTaskOrDate
    }
}
