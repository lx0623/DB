/*
 * AriesEngineShell.cpp
 *
 *  Created on: Mar 13, 2019
 *      Author: lichi
 */

#include "AriesEngineShell.h"
#include "AriesExprBridge.h"
#include "datatypes/AriesDatetimeTrans.h"

BEGIN_ARIES_ENGINE_NAMESPACE

    AriesEngineShell::AriesEngineShell()
    {
        // TODO Auto-generated constructor stub
    }

    AriesEngineShell::~AriesEngineShell()
    {
        // TODO Auto-generated destructor stub
    }

    // AriesScanNodeSPtr AriesEngineShell::MakeScanNode( int nodeId, const string& dbName, PhysicalTablePointer arg_table, const vector< int >& arg_columns_id )
    // {
    //     return AriesNodeManager::MakeScanNode( nodeId, dbName, arg_table, arg_columns_id );
    // }

    AriesMvccScanNodeSPtr AriesEngineShell::MakeMvccScanNode( int nodeId, const AriesTransactionPtr& tx, const string& dbName, const string& tableName,
            const vector< int >& arg_columns_id )
    {
        return AriesNodeManager::MakeMvccScanNode( nodeId, tx, dbName, tableName, arg_columns_id );
    }

    static void ConvertConstConditionExpr( AriesCommonExprUPtr& expr )
    {
        AriesExprType exprType = expr->GetType();
        AriesColumnType valueType = expr->GetValueType();

        AriesExprType resultExprType = AriesExprType::TRUE_FALSE;
        AriesValueType _type = AriesValueType::BOOL;
        aries::AriesDataType data_type{_type, 1};
        AriesColumnType resultValueType{ data_type, false, false };

        auto exprId = expr->GetId();
        switch ( exprType )
        {
            case AriesExprType::INTEGER:
            {
                switch ( valueType.DataType.ValueType )
                {
                    case AriesValueType::INT32:
                    {
                        auto content = boost::get<int>( expr->GetContent() );
                        expr = AriesCommonExpr::Create( resultExprType, 0 == content ? false : true, resultValueType );
                        break;
                    }
                    case AriesValueType::INT64:
                    {
                        auto content = boost::get<int64_t>( expr->GetContent() );
                        expr = AriesCommonExpr::Create( resultExprType, 0 == content ? false : true, resultValueType );
                        break;
                    }

                    default:
                        ARIES_ASSERT( 0, "unexpected value type: " + std::to_string( (int) valueType.DataType.ValueType ) );
                        break;
                }
                break;
            }

            case AriesExprType::FLOATING:
            {
                auto content = boost::get<double>( expr->GetContent() );
                expr = AriesCommonExpr::Create( resultExprType, 0 == content ? false : true, resultValueType );
                break;
            }

            case AriesExprType::DECIMAL:
            {
                auto content = boost::get<aries_acc::Decimal>( expr->GetContent() );
                expr = AriesCommonExpr::Create( resultExprType, 0 == content ? false : true, resultValueType );
                break;
            }

            case AriesExprType::STRING:
            {
                auto content = boost::get<std::string>( expr->GetContent() );
                int32_t i = 1;
                try
                {
                    i = std::stoi( content );
                }
                catch( std::invalid_argument &e )
                {
                    i = 0;
                }
                catch( ... )
                {
                    // ignore any other exceptions
                }
                
                expr = AriesCommonExpr::Create( resultExprType, 0 == i ? false : true, resultValueType );
                break;
            }

            case AriesExprType::DATE:
            {
                auto content = boost::get<aries_acc::AriesDate>( expr->GetContent() );
                expr = AriesCommonExpr::Create( resultExprType, AriesDatetimeTrans::GetInstance().ToBool( content ), resultValueType );
                break;
            }
            case AriesExprType::DATE_TIME:
            {
                auto content = boost::get<aries_acc::AriesDatetime>( expr->GetContent() );
                expr = AriesCommonExpr::Create( resultExprType, AriesDatetimeTrans::GetInstance().ToBool( content ), resultValueType );
                break;
            }
            case AriesExprType::TIME:
            {
                auto content = boost::get<aries_acc::AriesTime>( expr->GetContent() );
                expr = AriesCommonExpr::Create( resultExprType, AriesDatetimeTrans::GetInstance().ToBool( content ), resultValueType );
                break;
            }
            case AriesExprType::TIMESTAMP:
            {
                auto content = boost::get<aries_acc::AriesTimestamp>( expr->GetContent() );
                expr = AriesCommonExpr::Create( resultExprType, AriesDatetimeTrans::GetInstance().ToBool( content ), resultValueType );
                break;
            }
            case AriesExprType::YEAR:
            {
                auto content = boost::get<aries_acc::AriesYear>( expr->GetContent() );
                expr = AriesCommonExpr::Create( resultExprType, AriesDatetimeTrans::GetInstance().ToBool( content ), resultValueType );
                break;
            }

            case AriesExprType::NULL_VALUE:
                expr = AriesCommonExpr::Create( resultExprType, false, resultValueType );
                break;
        
            default:
                break;
        }
        expr->SetId( exprId );
    }

    AriesFilterNodeSPtr AriesEngineShell::MakeFilterNode( int nodeId, BiaodashiPointer arg_filter_expr, const vector< int >& arg_columns_id )
    {
        AriesExprBridge bridge;
        AriesCommonExprUPtr expr = bridge.Bridge( arg_filter_expr );
        int exprId = 0;
        expr->SetId( ++exprId );
        ConvertConstConditionExpr( expr );
        return AriesNodeManager::MakeFilterNode( nodeId, expr, arg_columns_id );
    }

    AriesGroupNodeSPtr AriesEngineShell::MakeGroupNode( int nodeId, const vector< BiaodashiPointer >& arg_group_by_exprs,
            const vector< BiaodashiPointer >& arg_select_exprs )
    {
        int exprId = 0;
        AriesExprBridge bridge;
        vector< AriesCommonExprUPtr > sels;
        for( const auto& sel : arg_select_exprs )
        {
            sels.push_back( bridge.Bridge( sel ) );
            sels.back()->SetId( ++exprId );
        }

        vector< AriesCommonExprUPtr > groups;
        for( const auto& group : arg_group_by_exprs )
        {
            auto bridged = bridge.Bridge( group );
            if( !bridged->IsLiteralValue() )
            {
                bridged->SetId( ++exprId );
                groups.push_back( std::move( bridged ) );
            }
            else
            {
                LOG(INFO)<< "constant expression in group-by clause was filtered here.";
            }
        }
        return AriesNodeManager::MakeGroupNode( nodeId, groups, sels );
    }

    AriesSortNodeSPtr AriesEngineShell::MakeSortNode( int nodeId, const vector< BiaodashiPointer >& arg_order_by_exprs,
            const vector< OrderbyDirection >& arg_order_by_directions, const vector< int >& arg_columns_id )
    {
        int exprId = 0;
        AriesExprBridge bridge;
        vector< AriesCommonExprUPtr > exprs;
        for( const auto& expr : arg_order_by_exprs )
        {
            exprs.push_back( bridge.Bridge( expr ) );
            exprs.back()->SetId( ++exprId );
        }
        return AriesNodeManager::MakeSortNode( nodeId, exprs, bridge.ConvertToAriesOrderType( arg_order_by_directions ), arg_columns_id );
    }

    AriesJoinNodeSPtr AriesEngineShell::MakeJoinNode( int nodeId, BiaodashiPointer equal_join_expr, BiaodashiPointer other_join_expr, int arg_join_hint,
            bool arg_join_hint_2, const vector< int > &arg_columns_id )
    {
        int exprId = 0;
        AriesExprBridge bridge;
        AriesCommonExprUPtr equal = equal_join_expr ? bridge.Bridge( equal_join_expr ) : nullptr;
        AriesCommonExprUPtr other = other_join_expr ? bridge.Bridge( other_join_expr ) : nullptr;
        if( equal )
            equal->SetId( ++exprId );
        if( other )
        {
            other->SetId( ++exprId );
            ConvertConstConditionExpr( other );
        }
        return AriesNodeManager::MakeJoinNode( nodeId, std::move( equal ), std::move( other ), AriesJoinType::INNER_JOIN, arg_join_hint, arg_join_hint_2, arg_columns_id );
    }

    AriesJoinNodeSPtr AriesEngineShell::MakeJoinNodeComplex( int nodeId, BiaodashiPointer equal_join_expr, BiaodashiPointer other_join_expr,
            JoinType arg_join_type, const vector< int > &arg_columns_id )
    {
        int exprId = 0;
        AriesExprBridge bridge;
        AriesCommonExprUPtr equal = equal_join_expr ? bridge.Bridge( equal_join_expr ) : nullptr;
        AriesCommonExprUPtr other = other_join_expr ? bridge.Bridge( other_join_expr ) : nullptr;
        if( equal )
            equal->SetId( ++exprId );
        if( other )
        {
            other->SetId( ++exprId );
            ConvertConstConditionExpr( other );
        }
        return AriesNodeManager::MakeJoinNodeComplex( nodeId, std::move( equal ), std::move( other ), bridge.ConvertToAriesJoinType( arg_join_type ), arg_columns_id );
    }

    AriesColumnNodeSPtr AriesEngineShell::MakeColumnNode( int nodeId, const vector< BiaodashiPointer >& arg_select_exprs, const vector< int >& arg_columns_id,
            int arg_mode )
    {
        int exprId = 0;
        AriesExprBridge bridge;
        vector< AriesCommonExprUPtr > exprs;
        for( const auto& expr : arg_select_exprs )
        {
            exprs.push_back( bridge.Bridge( expr ) );
            exprs.back()->SetId( ++exprId );
        }
        return AriesNodeManager::MakeColumnNode( nodeId, exprs, arg_mode, arg_columns_id );
    }

    AriesUpdateCalcNodeSPtr AriesEngineShell::MakeUpdateCalcNode( int nodeId, const vector< BiaodashiPointer >& arg_select_exprs,
            const vector< int >& arg_columns_id )
    {
        int exprId = 0;
        AriesExprBridge bridge;
        vector< AriesCommonExprUPtr > exprs;
        for( const auto& expr : arg_select_exprs )
        {
            exprs.push_back( bridge.Bridge( expr ) );
            exprs.back()->SetId( ++exprId );
        }
        return AriesNodeManager::MakeUpdateCalcNode( nodeId, exprs, arg_columns_id );
    }

    AriesOutputNodeSPtr AriesEngineShell::MakeOutputNode()
    {
        return AriesNodeManager::MakeOutputNode();
    }

    AriesLimitNodeSPtr AriesEngineShell::MakeLimitNode( int nodeId, int64_t offset, int64_t size )
    {
        return AriesNodeManager::MakeLimitNode( nodeId, offset, size );
    }

    AriesSetOperationNodeSPtr AriesEngineShell::MakeSetOpNode( int nodeId, SetOperationType type )
    {
        AriesExprBridge bridge;
        return AriesNodeManager::MakeSetOpNode( nodeId, bridge.ConvertToAriesSetOpType( type ) );
    }

    AriesSelfJoinNodeSPtr AriesEngineShell::MakeSelfJoinNode( int nodeId, int joinColumnId, CommonBiaodashiPtr filter_expr,
            const vector< HalfJoinInfo >& join_info, const vector< int >& arg_columns_id )
    {
        int exprId = 0;
        AriesExprBridge bridge;
        SelfJoinParams joinParams;

        if( filter_expr )
        {
            joinParams.CollectedFilterConditionExpr = bridge.Bridge( filter_expr );
            joinParams.CollectedFilterConditionExpr->SetId( ++exprId );
        }

        for( const auto& info : join_info )
        {
            HalfJoinCondition condition;
            condition.JoinType = bridge.ConvertToAriesJoinType( info.HalfJoinType );
            assert( info.JoinConditionExpr );
            condition.JoinConditionExpr = bridge.Bridge( info.JoinConditionExpr );
            condition.JoinConditionExpr->SetId( ++exprId );
            joinParams.HalfJoins.push_back( std::move( condition ) );
        }

        return AriesNodeManager::MakeSelfJoinNode( nodeId, joinColumnId, joinParams, arg_columns_id );
    }

    AriesExchangeNodeSPtr AriesEngineShell::MakeExchangeNode( int nodeId, int dstDeviceId, const vector< int >& srcDeviceId )
    {
        return AriesNodeManager::MakeExchangeNode( nodeId, dstDeviceId, srcDeviceId );
    }

END_ARIES_ENGINE_NAMESPACE
/* namespace AriesEngine */
