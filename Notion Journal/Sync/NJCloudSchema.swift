import Foundation

enum NJOutlineCloudMapper {
    static let entity = "outline"
    static let recordType = "NJOutline"
}

enum NJOutlineNodeCloudMapper {
    static let entity = "outline_node"
    static let recordType = "NJOutlineNode"
}

enum NJPlanningNoteCloudMapper {
    static let entity = "planning_note"
    static let recordType = "NJPlanningNote"
}

enum NJFinanceTransactionCloudMapper {
    static let entity = "finance_transaction"
    static let recordType = "NJFinanceTransaction"
}

enum NJInvestmentLedgerTransactionCloudMapper {
    static let entity = "investment_ledger_transaction"
    static let recordType = "NJInvestmentLedgerTransaction"
}

enum NJInvestmentChartDrawingCloudMapper {
    static let entity = "investment_chart_drawing"
    static let recordType = "NJInvestmentChartDrawing"
}

enum NJInvestmentSymbolCloudMapper {
    static let entity = "investment_symbol"
    static let recordType = "NJInvestmentSymbol"
}

enum NJInvestmentSymbolRelationshipCloudMapper {
    static let entity = "investment_symbol_relationship"
    static let recordType = "NJInvestmentSymbolRelationship"
}

enum NJFinanceMacroEventCloudMapper {
    static let entity = "finance_macro_event"
    static let recordType = "NJFinanceMacroEvent"
}

enum NJCardSchemaCloudMapper {
    static let entity = "card_schema"
    static let recordType = "NJCardSchema"
}

enum NJCardCloudMapper {
    static let entity = "card"
    static let recordType = "NJCard"
}

enum NJTableCloudMapper {
    static let entity = "table"
    static let recordType = "NJTable"
}

enum NJHealthSampleCloudMapper {
    static let entity = "health_sample"
    static let recordType = "NJHealthSample"
}

enum NJAgentHeartbeatRunCloudMapper {
    static let entity = "agent_heartbeat_run"
    static let recordType = "NJAgentHeartbeatRun"
}

enum NJAgentBackfillTaskCloudMapper {
    static let entity = "agent_backfill_task"
    static let recordType = "NJAgentBackfillTask"
}

enum NJCloudSchema {
    // These local tables are intentionally present before the CloudKit schema is
    // deployed. Querying missing record types costs a network round trip and
    // logs CKError.unknownItem on every launch, so keep them out of the default
    // sync order until the private database schema exists.
    static let syncAgentAutomationTables = false

    static let syncOrder: [(String, String)] = {
        var a: [(String, String)] = []
        a.append((NJNotebookCloudMapper.entity, NJNotebookCloudMapper.recordType))
        a.append((NJTabCloudMapper.entity, NJTabCloudMapper.recordType))
        a.append((NJNoteCloudMapper.entity, NJNoteCloudMapper.recordType))
        a.append((NJTableCloudMapper.entity, NJTableCloudMapper.recordType))
        a.append((NJBlockCloudMapper.entity, NJBlockCloudMapper.recordType))
        a.append((NJAttachmentCloudMapper.entity, NJAttachmentCloudMapper.recordType))
        a.append((NJCalendarItemCloudMapper.entity, NJCalendarItemCloudMapper.recordType))
        a.append((NJPlannedExerciseCloudMapper.entity, NJPlannedExerciseCloudMapper.recordType))
        a.append((NJHealthSampleCloudMapper.entity, NJHealthSampleCloudMapper.recordType))
        a.append((NJPlanningNoteCloudMapper.entity, NJPlanningNoteCloudMapper.recordType))
        a.append((NJFinanceTransactionCloudMapper.entity, NJFinanceTransactionCloudMapper.recordType))
        a.append((NJInvestmentLedgerTransactionCloudMapper.entity, NJInvestmentLedgerTransactionCloudMapper.recordType))
        a.append((NJInvestmentChartDrawingCloudMapper.entity, NJInvestmentChartDrawingCloudMapper.recordType))
        a.append((NJInvestmentSymbolCloudMapper.entity, NJInvestmentSymbolCloudMapper.recordType))
        a.append((NJInvestmentSymbolRelationshipCloudMapper.entity, NJInvestmentSymbolRelationshipCloudMapper.recordType))
        a.append((NJFinanceMacroEventCloudMapper.entity, NJFinanceMacroEventCloudMapper.recordType))
        if syncAgentAutomationTables {
            a.append((NJAgentHeartbeatRunCloudMapper.entity, NJAgentHeartbeatRunCloudMapper.recordType))
            a.append((NJAgentBackfillTaskCloudMapper.entity, NJAgentBackfillTaskCloudMapper.recordType))
        }
        a.append((NJTimeSlotCloudMapper.entity, NJTimeSlotCloudMapper.recordType))
        a.append((NJPersonalGoalCloudMapper.entity, NJPersonalGoalCloudMapper.recordType))
        a.append((NJRenewalItemCloudMapper.entity, NJRenewalItemCloudMapper.recordType))
        a.append((NJCardSchemaCloudMapper.entity, NJCardSchemaCloudMapper.recordType))
        a.append((NJCardCloudMapper.entity, NJCardCloudMapper.recordType))
        a.append(("goal", "NJGoal"))
        a.append((NJOutlineCloudMapper.entity, NJOutlineCloudMapper.recordType))
        a.append((NJOutlineNodeCloudMapper.entity, NJOutlineNodeCloudMapper.recordType))
        a.append((NJNoteBlockCloudMapper.entity, NJNoteBlockCloudMapper.recordType))
        return a
    }()
}
