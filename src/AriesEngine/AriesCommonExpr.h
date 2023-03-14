//
// Created by 胡胜刚 on 2019-07-22.
//

#pragma once

#include <set>
#include <boost/variant.hpp>
#include "AriesUtil.h"

using namespace aries_acc;
using namespace aries;

BEGIN_ARIES_ENGINE_NAMESPACE

    AriesDataBufferSPtr ConstExprContentToDataBuffer( const AriesExprContent& content, size_t tupleNum );

    class AriesCommonExpr;

    using AriesExpressionContent = AriesExprContent;
    using AriesCommonExprUPtr = std::unique_ptr<AriesCommonExpr>;

    class AriesCommonExpr: protected DisableOtherConstructors
    {
    private:
        AriesExprType type;
        bool useDictIndex; // 对于字典压缩的列，是否使用字典索引数据进行比较计算
        AriesExpressionContent content;
        AriesColumnType value_type;

        std::vector< AriesCommonExprUPtr > children;
        int m_id;// the id should be unique with in a AriesOpNode.

    private:
        static map< AriesCalculatorOpType, string > calcOpToStr;
        static map< AriesAggFunctionType, string > aggFuncToStr;

    public:
        AriesCommonExprUPtr Clone() const;

        void SetId( int& id );

        int GetId() const;

        static AriesCommonExprUPtr Create( AriesExprType type, AriesExpressionContent content, AriesColumnType value_type );

        ~AriesCommonExpr();

        void AddChild( AriesCommonExprUPtr child );

        int GetChildrenCount() const;

        const AriesCommonExprUPtr &GetChild( int index ) const;

        AriesExprType GetType() const;

        void SetType( AriesExprType type );

        const AriesExpressionContent &GetContent() const;

        void SetContent( const AriesExpressionContent &content );

        AriesColumnType GetValueType() const;

        void SetValueType( AriesColumnType value_type );

        bool IsDistinct() const;

        std::string StringForDynamicCode( std::map< string, AriesCommonExprUPtr > &aggFunctions,
                                          vector< AriesDynamicCodeParam >& ariesParams,
                                          vector< AriesDataBufferSPtr >& constValues,
                                          vector< AriesDynamicCodeComparator >& ariesComparators );

        AriesAggFunctionType GetAggFunctionType() const;

        AriesSqlFunctionType GetSqlFunctionType() const;

        bool IsLiteralValue() const;

        bool IsEqualExpression() const;

        bool IsAddExpression() const;

        void SetUseDictIndex( bool b );

        bool IsUseDictIndex() const;

        AriesCommonExpr( AriesExprType _type, AriesExpressionContent _content, AriesColumnType _value_type );

        string ToString() const;

        string GetIntervalUnitTypeName() const;

    private:
        std::string stringForDynamicCodeInternal( std::map< string, AriesCommonExprUPtr > &aggFunctions,
                                                  int &seq,
                                                  set< AriesDynamicCodeParam >& ariesParams,
                                                  vector< AriesDataBufferSPtr >& constValues,
                                                  vector< AriesDynamicCodeComparator >& ariesComparators,
                                                  bool printConstAsLiteral = false );

        std::string stringForSqlFunctions( std::map< string, AriesCommonExprUPtr > &aggFunctions,
                                           int &seq, set< AriesDynamicCodeParam >& ariesParams,
                                           vector< AriesDataBufferSPtr >& constValues,
                                           vector< AriesDynamicCodeComparator >& ariesComparators,
                                           bool printConstAsLiteral = false );

        std::string contentToString( set< AriesDynamicCodeParam >& ariesParams,
                                     vector< AriesDataBufferSPtr >& constValues,
                                     bool printConstAsLiteral = false ) const;

        std::string generateCompareFunctionHeader( AriesComparisonOpType op, bool leftHasNull, bool rightHasNull ) const;

        std::string makeNullLiteral( AriesColumnType type ) const;

        std::string generateCodeForUNIX_TIMESTAMP( const AriesCommonExprUPtr& expr, vector< AriesDynamicCodeParam >& ariesParams );

        AriesDataBufferSPtr ConvertLiteralArrayToDataBuffer( AriesColumnType dataType, bool bHasNot ) const;
    };

END_ARIES_ENGINE_NAMESPACE
// namespace aries
