import XCTest
import ToughTrialV2Core

final class V2AssistantWriteIntentTests: XCTestCase {
    func testColloquialBreakdownRequestIsAuthorizedButNegationAndDiscussionAreNot() {
        for text in ["来分一下这个任务喽", "帮我拆一下这个任务", "把这个任务细分一下", "分一分这个任务", "拆小一点"] {
            XCTAssertTrue(V2AssistantWriteIntent.authorize(text, hasTaskReference: true), text)
        }
        for text in ["hello", "先不要分一下这个任务", "如果分一下这个任务会怎样", "这个任务为什么没有拆开"] {
            XCTAssertFalse(V2AssistantWriteIntent.authorize(text, hasTaskReference: true), text)
        }
    }

    func testGreetingAfterFailedScheduleCannotInheritWriteAuthority() {
        let priorMessages = [
            V2AgentMessage.userText("排到今天"),
            V2AgentMessage(
                role: .agent,
                parts: [.error(.retryable("排期失败"))],
                createdAt: Date(),
                status: .failed
            )
        ]

        XCTAssertFalse(
            V2AssistantWriteIntent.authorize(
                "hello",
                priorMessages: priorMessages
            )
        )
    }

    func testExplicitTodaySchedulingIsAuthorized() {
        XCTAssertTrue(V2AssistantWriteIntent.authorize("排到今天吧"))
    }

    func testNegatedCreationIsNotAuthorized() {
        XCTAssertFalse(V2AssistantWriteIntent.authorize("不要创建任务：买牛奶"))
    }

    func testExplicitCreationIsAuthorized() {
        XCTAssertTrue(V2AssistantWriteIntent.authorize("创建任务：买牛奶"))
    }

    func testGreetingsAreNeverWriteIntent() {
        for text in ["hello", "你好", "谢谢"] {
            XCTAssertFalse(V2AssistantWriteIntent.authorize(text), text)
        }
    }

    func testDiscussionAndFeedbackAreNotWriteIntent() {
        for text in ["如果创建任务会怎样？", "为什么没进入今天？", "刚才排期失败了"] {
            XCTAssertFalse(V2AssistantWriteIntent.authorize(text), text)
        }
    }

    func testNegatedScheduleAndArchiveAreNotWriteIntent() {
        for text in ["先别排到今天", "不要归档这个任务"] {
            XCTAssertFalse(V2AssistantWriteIntent.authorize(text), text)
        }
    }

    func testPoliteTaskBreakdownWithSelectedTaskIsAuthorized() {
        XCTAssertTrue(
            V2AssistantWriteIntent.authorize(
                "能不能帮我拆分一下任务啊？",
                hasTaskReference: true
            )
        )
    }

    func testTaskBreakdownWithoutReferenceRemainsAmbiguous() {
        XCTAssertFalse(V2AssistantWriteIntent.authorize("能不能帮我拆分一下任务啊？"))
    }

    func testDirectWriteVerbsAuthorizeAcrossTaskOperations() {
        for text in [
            "创建任务：准备周报",
            "把准备周报改到明天",
            "排到今天吧",
            "完成准备周报",
            "归档准备周报"
        ] {
            XCTAssertTrue(V2AssistantWriteIntent.authorize(text), text)
        }
    }

    func testPoliteWriteQuestionIsStillExplicitIntent() {
        XCTAssertTrue(V2AssistantWriteIntent.authorize("可以帮我把任务排到今天吗？"))
    }

    func testExplicitFinanceAndCaptureWritesAreAuthorized() {
        for text in [
            "创建订阅：音乐会员",
            "已付款，请记录",
            "设置预算：本月餐饮 2000 元",
            "记录今天午饭 20 美元",
            "记下灵感：把这段对话整理成文章"
        ] {
            XCTAssertTrue(V2AssistantWriteIntent.authorize(text), text)
        }
    }

    func testReadOnlyQueriesAreNotWriteIntent() {
        for text in ["查看最近记录", "帮我看看预算进度", "查询订阅计划"] {
            XCTAssertFalse(V2AssistantWriteIntent.authorize(text), text)
        }
    }

    func testBoundedNegationsDoNotCancelAnExplicitWrite() {
        for text in [
            "新增明天下午四点写周报，其他任务不要动",
            "把刚才那个改到后天下午五点，时长和备注保持不变，不要新增任务",
            "新增准备演示，拆成收集资料和写提纲两个子任务"
        ] {
            XCTAssertTrue(V2AssistantWriteIntent.authorize(text), text)
        }
    }

    func testNegatedDateSchedulingRemainsDenied() {
        XCTAssertFalse(V2AssistantWriteIntent.authorize("先不要安排日期"))
    }

    func testBreakdownNegationsAreNotAuthorized() {
        for text in ["请不要拆分这个任务", "能不能先不要拆分这个任务"] {
            XCTAssertFalse(V2AssistantWriteIntent.authorize(text), text)
        }
    }

    func testNegatedAdditionCanStillAuthorizeIndependentBreakdown() {
        XCTAssertTrue(
            V2AssistantWriteIntent.authorize("不要新增，只拆分这个任务")
        )
    }

    func testValidClarificationReplyInheritsAdjacentSuccessfulWriteIntent() {
        let priorMessages = [
            V2AgentMessage.userText("把准备周报排到今天"),
            V2AgentMessage.agentText("请确认任务日期是今天吗？")
        ]

        XCTAssertTrue(
            V2AssistantWriteIntent.authorize(
                "是就今天，然后其他的没问题",
                priorMessages: priorMessages
            )
        )
    }

    func testClarificationReplyWithoutAdjacentWriteDoesNotAuthorize() {
        let priorMessages = [
            V2AgentMessage.agentText("请确认任务日期是今天吗？")
        ]

        XCTAssertFalse(
            V2AssistantWriteIntent.authorize(
                "是就今天，然后其他的没问题",
                priorMessages: priorMessages
            )
        )
    }

    func testFailedClarificationCannotInheritWriteIntent() {
        let priorMessages = [
            V2AgentMessage.userText("把准备周报排到今天"),
            V2AgentMessage(
                role: .agent,
                parts: [.error(.retryable("网络失败"))],
                createdAt: Date(),
                status: .failed
            )
        ]

        XCTAssertFalse(
            V2AssistantWriteIntent.authorize(
                "是就今天，然后其他的没问题",
                priorMessages: priorMessages
            )
        )
    }

    func testNonAdjacentClarificationCannotInheritHistoricalWriteIntent() {
        let priorMessages = [
            V2AgentMessage.userText("把准备周报排到今天"),
            V2AgentMessage.agentText("请确认任务日期是今天吗？"),
            V2AgentMessage.userText("hello"),
            V2AgentMessage.agentText("请确认任务日期是今天吗？")
        ]

        XCTAssertFalse(
            V2AssistantWriteIntent.authorize(
                "是就今天，然后其他的没问题",
                priorMessages: priorMessages
            )
        )
    }

    func testBareAgreementNeedsAnExplicitWriteConfirmationQuestion() {
        let priorMessages = [
            V2AgentMessage.userText("创建任务：准备周报"),
            V2AgentMessage.agentText("具体要做什么？")
        ]

        XCTAssertFalse(
            V2AssistantWriteIntent.authorize(
                "好",
                priorMessages: priorMessages
            )
        )
    }

    func testBareAgreementCanConfirmAnAdjacentWriteDateQuestion() {
        let priorMessages = [
            V2AgentMessage.userText("把准备周报排到今天"),
            V2AgentMessage.agentText("要排到今天吗？")
        ]

        XCTAssertTrue(
            V2AssistantWriteIntent.authorize(
                "好",
                priorMessages: priorMessages
            )
        )
    }

    func testBareAgreementCannotInheritFromNegatedPredecessor() {
        let priorMessages = [
            V2AgentMessage.userText("不要新增任务"),
            V2AgentMessage.agentText("要排到今天吗？")
        ]

        XCTAssertFalse(
            V2AssistantWriteIntent.authorize(
                "好",
                priorMessages: priorMessages
            )
        )
    }
}
