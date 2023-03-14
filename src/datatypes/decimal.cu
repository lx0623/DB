/*
 * decimal.cxx
 *
 *  Created on: 2019年6月26日
 *      Author: david
 */
#include "decimal.hxx"
#include <cassert>
#include <cmath>
#include "AriesDataTypeUtil.hxx"


BEGIN_ARIES_ACC_NAMESPACE

#define FIX_INTG_FRAC_ERROR(len, intg1, frac1, error)       \
    do                                                      \
    {                                                       \
        if (intg1+frac1 > (len))                            \
        {                                                   \
            if (intg1 > (len))                              \
            {                                               \
                intg1=(len);                                \
                frac1=0;                                    \
                error=ERR_OVER_FLOW;                        \
            }                                               \
            else                                            \
            {                                               \
                frac1=(len)-intg1;                          \
                error=ERR_TRUNCATED;                        \
            }                                               \
        }                                                   \
        else                                                \
        {                                                   \
            error=ERR_OK;                                   \
        }                                                   \
    } while(0)

#define FIX_TAGET_INTG_FRAC_ERROR(len, intg1, frac1, error) \
    do                                                      \
    {                                                       \
        if (intg1+frac1 > (len))                            \
        {                                                   \
            if (frac1 > (len))                              \
            {                                               \
                intg1=(len);                                \
                frac1=0;                                    \
                error=ERR_OVER_FLOW;                        \
            }                                               \
            else                                            \
            {                                               \
                intg1=(len)-frac1;                          \
                error=ERR_TRUNCATED;                        \
            }                                               \
        }                                                   \
        else                                                \
        {                                                   \
            error=ERR_OK;                                   \
        }                                                   \
    } while(0)

#define SET_PREC_SCALE_VALUE(t, d0, d1, d2) (t = (d1 != d2 ? d1 * DIG_PER_INT32 : d0))

    ARIES_HOST_DEVICE_NO_INLINE Decimal::Decimal() : Decimal(DEFAULT_PRECISION, DEFAULT_SCALE) {}

//    ARIES_HOST_DEVICE_NO_INLINE Decimal::Decimal( const Decimal& d )
//    {
//        intg = d.intg;
//        frac = d.frac;
//        mode = d.mode;
//        error = d.error;
//        for( int i = 0; i < NUM_TOTAL_DIG; i++ )
//        {
//            values[i] = d.values[i];
//        }
//    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal::Decimal(uint32_t precision, uint32_t scale) : Decimal(precision, scale, (uint32_t) ARIES_MODE_EMPTY) {
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal::Decimal(uint32_t precision, uint32_t scale, uint32_t m) {
        initialize(precision - scale, scale, m);
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal::Decimal(uint32_t precision, uint32_t scale, const char s[]) : Decimal( precision, scale, ARIES_MODE_EMPTY, s) {
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal::Decimal(uint32_t precision, uint32_t scale, uint32_t m, const char s[] ) {
        initialize(precision - scale, scale, m);
        Decimal d(s);
        cast(d);
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal::Decimal(const CompactDecimal *compact, uint32_t precision, uint32_t scale, uint32_t m) {
        initialize(precision - scale, scale, m);
        SignPos signPos;
        int fracBits = GetDecimalNeedBits(frac);
        int intgBits = GetDecimalNeedBits(intg);
        int realFracBytes = NEEDBYTES(fracBits);
        int realIntgBytes = NEEDBYTES(intgBits);
        if (HAS_FREE_BIT(intgBits)) {
            signPos = INTG_PART;
        } else if (HAS_FREE_BIT(fracBits)) {
            signPos = FRAC_PART;
        } else {
            signPos = ADDITIONAL_PART;
        }
        int sign = 0;
        //handle frag part
        int fracInts = NEEDELEMENTS(frac);
        if (realFracBytes) {
            aries_memcpy((char *)(values + (NUM_TOTAL_DIG - fracInts) ), compact->data + realIntgBytes, realFracBytes);
            if (signPos == FRAC_PART) {
                char *temp = ((char *)(values + INDEX_LAST_DIG));
                if (GET_COMPACT_BYTES(realFracBytes) == realFracBytes) {
                    // <= 3 bytes only
                    temp += GET_COMPACT_BYTES(realFracBytes) - 1;
                } else {
                    // >=4 bytes, have one sort
                    if(GET_COMPACT_BYTES(realFracBytes) != 0)
                        temp -= 1;
                    else
                        temp += 3;
                }
                sign = GET_SIGN_FROM_BIT(*temp);
                *temp = *temp & 0x7f;
            }
            if (GET_COMPACT_BYTES(realFracBytes)) {
                values[INDEX_LAST_DIG] = values[INDEX_LAST_DIG] * GetPowers10( DIG_PER_INT32 - frac % DIG_PER_INT32);
            }
        }
        //handle intg part
        if (realIntgBytes) {
            int wholeInts = GET_WHOLE_INTS(realIntgBytes);
            int compactPart = GET_COMPACT_BYTES(realIntgBytes);
            int pos = NUM_TOTAL_DIG - (fracInts + NEEDELEMENTS(intg));
            if (compactPart) {
                if (wholeInts) {
                    aries_memcpy((char *)(values + (pos + 1)), compact->data + compactPart, realIntgBytes - compactPart);
                }
                aries_memcpy((char *)(values + pos), compact->data, compactPart);
            } else if (wholeInts) {
                aries_memcpy((char *)(values + pos), compact->data, realIntgBytes);
            }
            if (signPos == INTG_PART) {
                char *temp = ((char *)(values + (INDEX_LAST_DIG - fracInts)));
                if (compactPart == realIntgBytes) {
                    // <= 3 bytes only
                    temp += compactPart - 1;
                } else {
                    // >=4 bytes, have one sort
                    temp += 3;
                }
                sign = GET_SIGN_FROM_BIT(*temp);
                *temp = *temp & 0x7f;
            }
        }
        if (signPos == ADDITIONAL_PART) {
            sign = compact->data[realFracBytes + realIntgBytes];
        }
        if (sign) {
            Negate();
        }
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal::Decimal(const char s[]) {
        initialize(0, 0, 0);
        bool success = StringToDecimal((char *) s);
        if (!success) {
            SET_ERR(error, ERR_STR_2_DEC);
        }
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal::Decimal( const char* s, int len )
    {
        initialize(0, 0, 0);
        bool success = StringToDecimal((char *) s, len );
        if (!success) {
            SET_ERR(error, ERR_STR_2_DEC);
        }
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal::Decimal(int8_t v) {
        initialize(TINYINT_PRECISION, DEFAULT_SCALE, ARIES_MODE_EMPTY);
        values[INDEX_LAST_DIG] = v;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal::Decimal(int16_t v) {
        initialize(SMALLINT_PRECISION, DEFAULT_SCALE, ARIES_MODE_EMPTY);
        values[INDEX_LAST_DIG] = v;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal::Decimal(int32_t v) {
        initialize(INT_PRECISION, DEFAULT_SCALE, ARIES_MODE_EMPTY);
        values[INDEX_LAST_DIG - 1] = v / PER_DEC_MAX_SCALE;
        values[INDEX_LAST_DIG] = v % PER_DEC_MAX_SCALE;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal::Decimal(int64_t v) {
        initialize(BIGINT_PRECISION, DEFAULT_SCALE, ARIES_MODE_EMPTY);
        int64_t t = v / PER_DEC_MAX_SCALE;
        values[INDEX_LAST_DIG - 2] = t / PER_DEC_MAX_SCALE;
        values[INDEX_LAST_DIG - 1] = t % PER_DEC_MAX_SCALE;
        values[INDEX_LAST_DIG] = v % PER_DEC_MAX_SCALE;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal::Decimal(uint8_t v) {
        initialize(TINYINT_PRECISION, DEFAULT_SCALE, ARIES_MODE_EMPTY);
        values[INDEX_LAST_DIG] = v;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal::Decimal(uint16_t v) {
        initialize(SMALLINT_PRECISION, DEFAULT_SCALE, ARIES_MODE_EMPTY);
        values[INDEX_LAST_DIG] = v;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal::Decimal(uint32_t v) {
        initialize(INT_PRECISION, DEFAULT_SCALE, ARIES_MODE_EMPTY);
        values[INDEX_LAST_DIG - 1] = v / PER_DEC_MAX_SCALE;
        values[INDEX_LAST_DIG] = v % PER_DEC_MAX_SCALE;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal::Decimal(uint64_t v) {
        initialize(BIGINT_PRECISION, DEFAULT_SCALE, ARIES_MODE_EMPTY);
        int64_t t = v / PER_DEC_MAX_SCALE;
        values[INDEX_LAST_DIG - 2] = t / PER_DEC_MAX_SCALE;
        values[INDEX_LAST_DIG - 1] = t % PER_DEC_MAX_SCALE;
        values[INDEX_LAST_DIG] = v % PER_DEC_MAX_SCALE;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool Decimal::ToCompactDecimal(char * buf, int len) {
        SignPos signPos;
        int fracBits = GetDecimalNeedBits(frac);
        int intgBits = GetDecimalNeedBits(intg);
        int compactFracBytes = NEEDBYTES(fracBits);
        int compactIntgBytes = NEEDBYTES(intgBits);
        if (HAS_FREE_BIT(intgBits)) {
            signPos = INTG_PART;
        } else if (HAS_FREE_BIT(fracBits)) {
            signPos = FRAC_PART;
        } else {
            signPos = ADDITIONAL_PART;
        }
        if (len != compactFracBytes + compactIntgBytes + (signPos == ADDITIONAL_PART)) {
            return false;
        }
        int sign = 0;
        if (isLessZero()) {
            sign = 1;
            Negate();
        }
        //handle Frac part
        int usedInts = NEEDELEMENTS(frac);
        if (compactFracBytes) {
            int compactPart = GET_COMPACT_BYTES(compactFracBytes);
            if (compactFracBytes != compactPart) {
                aries_memcpy(buf + compactIntgBytes, (char *)(values + (NUM_TOTAL_DIG - usedInts)), compactFracBytes - compactPart);
            }
            if (compactPart) {
                int v = values[INDEX_LAST_DIG] / GetPowers10(DIG_PER_INT32 - frac % DIG_PER_INT32);
                aries_memcpy(buf + (compactIntgBytes + compactFracBytes - compactPart), (char *)&v, compactPart);
            }
            if (signPos == FRAC_PART) {
                int signBytePos = compactIntgBytes + compactFracBytes - 1;
                //has at last one Integer, use last byte of last one Integer
                if (compactFracBytes != compactPart) {
                    signBytePos -= compactPart;
                }
                assert((buf[signBytePos] & 0x80) == 0x0);
                SET_SIGN_BIT(buf[signBytePos], sign);
            }
        }
        //handle Intg part
        if (compactIntgBytes) {
            usedInts += NEEDELEMENTS(intg); //used to indicating total used Ints
            int wholeInts = GET_WHOLE_INTS(compactIntgBytes);
            int compactPart = GET_COMPACT_BYTES(compactIntgBytes);
            if (compactPart) {
                if (wholeInts) {
                    aries_memcpy(buf + compactPart, (char *)(values + (NUM_TOTAL_DIG - usedInts + 1)), compactIntgBytes - compactPart);
                }
                aries_memcpy(buf, (char *)(values + (NUM_TOTAL_DIG - usedInts)), compactPart);
            } else if (wholeInts) {
                aries_memcpy(buf, (char *)(values + (NUM_TOTAL_DIG - usedInts)), compactIntgBytes);
            }
            if (signPos == INTG_PART) {
                //sign bit is in last byte of intg part
                assert((buf[compactIntgBytes - 1] & 0x80) == 0x0);
                SET_SIGN_BIT(buf[compactIntgBytes - 1], sign);
            }
        }
        if (signPos == ADDITIONAL_PART) {
            buf[compactFracBytes + compactIntgBytes] = (char)sign;
        }

        if (sign) {
            Negate();
        }
        return true;
    }

    ARIES_HOST_DEVICE_NO_INLINE char *Decimal::GetInnerPrecisionScale(char result[]) {
        char temp[8];
        aries_sprintf(temp, "%d", intg + frac);
        aries_strcpy(result, temp);
        aries_strcat(result, ",");
        aries_sprintf((char *) temp, "%d", frac);
        aries_strcat(result, temp);
        return result;
    }

    ARIES_HOST_DEVICE_NO_INLINE char *Decimal::GetTargetPrecisionScale(char result[]) {
        return GetInnerPrecisionScale(result);
    }

    ARIES_HOST_DEVICE_NO_INLINE char *Decimal::GetPrecisionScale(char result[]) {
        if (GET_CALC_INTG(mode) + GET_CALC_FRAC(error) == 0) {
            return GetInnerPrecisionScale(result);
        }
        char temp[8];
        aries_sprintf(temp, "%d", GET_CALC_INTG(mode) + GET_CALC_FRAC(error));
        aries_strcpy(result, temp);
        aries_strcat(result, ",");
        aries_sprintf((char *) temp, "%d", GET_CALC_FRAC(error));
        aries_strcat(result, temp);
        return result;
    }

    ARIES_HOST_DEVICE_NO_INLINE uint16_t Decimal::GetSqlMode() {
        return GET_MODE(mode);
    }

    ARIES_HOST_DEVICE_NO_INLINE uint16_t Decimal::GetError() {
        return GET_ERR(error);
    }

    ARIES_HOST_DEVICE_NO_INLINE char *Decimal::GetInnerDecimal(char result[]) {
        char temp[16];
        int frac0 = NEEDELEMENTS(frac);
        //check sign
        bool postive = true;
        #pragma unroll
        for (int i = 0; i < NUM_TOTAL_DIG; i++) {
            if (values[i] < 0) {
                postive = false;
                break;
            }
        }
        //handle integer part
        int start = -1;
        int end = NUM_TOTAL_DIG - frac0;
        for (int i = 0; i < end; i++) {
            if (values[i] == 0)
                continue;
            start = i;
            break;
        }
        if (start == -1) {
            aries_strcpy(result, postive ? "0" : "-0");
        } else {
            aries_sprintf(result, "%d", values[start++]);
            for (int i = start; i < NUM_TOTAL_DIG - frac0; i++) {
                aries_sprintf(temp, values[i] < 0 ? "%010d" : "%09d", values[i]);
                aries_strcat(result, values[i] < 0 ? temp + 1 : temp);
            }
        }
        //handle frac part
        if (frac0) {
            aries_strcat(result, ".");
            int start = NUM_TOTAL_DIG - frac0;
            for ( int i = start; i < start + frac / DIG_PER_INT32; i++) {
                aries_sprintf(temp, values[i] < 0 ? "%010d" : "%09d", values[i]);
                aries_strcat(result, values[i] < 0 ? temp + 1 : temp);
            }
            //handle last one
            int remainLen = frac % DIG_PER_INT32;
            if (remainLen) {
                aries_sprintf(temp, values[INDEX_LAST_DIG] < 0 ? "%010d" : "%09d", values[INDEX_LAST_DIG]);
                aries_strncat(result, values[INDEX_LAST_DIG] < 0 ? temp + 1 : temp, remainLen);
            }
        }
        return result;
    }

    ARIES_HOST_DEVICE_NO_INLINE char * Decimal::GetDecimal(char result[]) {
        int frac0 = GET_CALC_FRAC(error), intg0 = GET_CALC_INTG(mode);
        if (frac0 == 0 && intg0 == 0) {
            return GetInnerDecimal(result);
        }
        if (frac0 != frac || intg0 != intg) {
            //need cast
            Decimal tmp(GET_CALC_INTG(mode) + GET_CALC_FRAC(error), GET_CALC_FRAC(error), GET_MODE(mode));
            SET_ERR(tmp.error, GET_ERR(error));
            tmp.cast(*this);
            return tmp.GetInnerDecimal(result);
        }
        return GetInnerDecimal(result);
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::CheckOverFlow() {
        int intg0 = intg == 0 ? 0 : NEEDELEMENTS(intg);
        int frac0 = frac == 0 ? 0 : NEEDELEMENTS(frac);
        int hiScale = intg0 * DIG_PER_INT32 - intg;
        bool neg = *this < 0;
        if (neg) {
            Negate();
        }
        //cross over values
        if (hiScale == 0) {
            intg0 += 1;
        } else {
            hiScale = DIG_PER_INT32 - hiScale;
        }
        int32_t hiMax = GetPowers10(hiScale) - 1;
        int st = NUM_TOTAL_DIG - frac0 - intg0;
        //check highest value
        int over = values[st] > hiMax ? 1 : 0;
        if (!over) {
            for (int i = 0; i < st; ++i) {
                if (values[i]) {
                    over = 1;
                    break;
                }
            }
        }
        if (over) {
            if (GET_MODE(mode) == ARIES_MODE_STRICT_ALL_TABLES) {
                SET_ERR(error, ERR_OVER_FLOW);
            }
            GenMaxDecByPrecision();
        }
        if (neg) {
            Negate();
        }
    }

    /*
     * integer/frac part by pos index
     *   0: value of 0 int
     *   1: value of 1 int
     *   2: value of 2 int
     *   3: value of 3 int
     * */
    ARIES_HOST_DEVICE_NO_INLINE void Decimal::setIntPart(int value, int pos) {
        int frac0 = NEEDELEMENTS(frac);
        int set = frac0 + pos;
        if (set < NUM_TOTAL_DIG) {
            values[INDEX_LAST_DIG - set] = value;
        }
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::setFracPart(int value, int pos) {
        int frac0 = NEEDELEMENTS(frac);
        if (pos < frac0) {
            values[INDEX_LAST_DIG - pos] = value;
        }
    }

    ARIES_HOST_DEVICE_NO_INLINE int Decimal::getIntPart(int pos) const {
        int frac0 = NEEDELEMENTS(frac);
        int get = frac0 + pos;
        if (get >= NUM_TOTAL_DIG) {
            return 0;
        }
        return values[INDEX_LAST_DIG - get];
    }

    ARIES_HOST_DEVICE_NO_INLINE int Decimal::getFracPart(int pos) const {
        int frac0 = NEEDELEMENTS(frac);
        if (pos >= frac0) {
            return 0;
        }
        return values[INDEX_LAST_DIG - pos];
    }

    //global method
    ARIES_HOST_DEVICE_NO_INLINE Decimal abs(Decimal decimal) {
        #pragma unroll
        for (int i = 0; i < NUM_TOTAL_DIG; i++) {
            if (decimal.values[i] < 0) {
                decimal.values[i] = -decimal.values[i];
            }
        }
        return decimal;
    }

    ARIES_HOST_DEVICE_NO_INLINE int GetDecimalRealBytes(uint16_t precision, uint16_t scale) {
        int fracBits = GetDecimalNeedBits(scale);
        int intgBits = GetDecimalNeedBits(precision - scale);
        if (HAS_FREE_BIT(fracBits) || HAS_FREE_BIT(intgBits)) {
            return NEEDBYTES(fracBits) +  NEEDBYTES(intgBits);
        } else {
            return NEEDBYTES(fracBits) +  NEEDBYTES(intgBits) + 1;
        }
    }

    ARIES_HOST_DEVICE_NO_INLINE int GetDecimalNeedBits(int base10Precision) {
        int len = base10Precision / DIG_PER_INT32 * 32;
        switch (base10Precision % DIG_PER_INT32) {
            case 0:
                len += 0;
                break;
            case 1:
                len += 4;
                break;
            case 2:
                len += 7;
                break;
            case 3:
                len += 10;
                break;
            case 4:
                len += 14;
                break;
            case 5:
                len += 17;
                break;
            case 6:
                len += 20;
                break;
            case 7:
                len += 24;
                break;
            case 8:
                len += 27;
                break;
        }
        return len;
    }

    ARIES_HOST_DEVICE_NO_INLINE int GetDecimalValidElementsCount( uint16_t precision, uint16_t scale )
    {
        return NEEDELEMENTS( precision - scale ) + NEEDELEMENTS( scale );
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal& Decimal::cast(const Decimal &v) {
        if (frac >= v.frac) {
            SET_ERR(error, GET_ERR(v.error));
            int shift = NEEDELEMENTS(frac) - NEEDELEMENTS(v.frac);
            for (int i = 0; i < shift; ++i) {
                values[i] = 0;
            }
            for (int i = shift; i < NUM_TOTAL_DIG; ++i) {
                values[i - shift] = v.values[i];
            }
            if (intg < v.intg) {
                CheckOverFlow();
            }
        } else {
            if (!v.isFracZero()) {
                int shift = NEEDELEMENTS(v.frac) - NEEDELEMENTS(frac);
                for (int i = 0; i < shift; ++i) {
                    values[i] = 0;
                }
                for (int i = shift; i < NUM_TOTAL_DIG; ++i) {
                    values[i] = v.values[i - shift];
                }
                bool neg = *this < 0;
                if (neg) {
                    Negate();
                }
                //scale down
                int scale = frac;
                if ( scale >= DIG_PER_INT32) {
                    scale %= DIG_PER_INT32;
                }
                if (scale) {
                    // scale 5: 123456789 -> 123460000
                    values[INDEX_LAST_DIG] = values[INDEX_LAST_DIG] / GetPowers10( DIG_PER_INT32 - scale) * GetPowers10( DIG_PER_INT32 - scale);
                }

                //check the carry if cast
                //scale 9, check 1 of next value
                if (++scale == 1) {
                    //use shift as index of values later, change check frac value index
                    --shift;
                }
                scale = DIG_PER_INT32 - scale;
                if (aries_abs(v.values[INDEX_LAST_DIG - shift] / GetPowers10(scale)) % 10 >= 5) {
                    int max = GetPowers10( DIG_PER_INT32);
                    int carry = scale + 1 == DIG_PER_INT32 ? 1 : GetPowers10( scale + 1);
                    for (int i = INDEX_LAST_DIG; i >= 0; --i) {
                        values[i] += carry;
                        if (values[i] < max) {
                            carry = 0;
                            break;
                        }
                        carry = 1;
                        values[i] = 0;
                    }
                    // check highest one
                    if (carry == 1) {
                        values[0] = max;
                    }
                }
                if (neg) {
                    Negate();
                }
            }
            CheckOverFlow();
        }
        assert(intg + frac <= SUPPORTED_MAX_PRECISION && frac <= SUPPORTED_MAX_SCALE);
        return *this;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal& Decimal::truncate( int p ) {
        uint16_t frac0 = frac, intg0 = intg;
        CalcInnerTruncatePrecision(p);
        CalcTruncatePrecision(p);
        if (p > 0) {
            p = frac;
        } else {
            if (-p >= intg0) {
                //result should be zero
                p = -(NEEDELEMENTS(intg0) + NEEDELEMENTS(frac0)) * DIG_PER_INT32;
            }
        }
        int shift = p >= 0 ? NEEDELEMENTS(frac0) - NEEDELEMENTS(p) : NEEDELEMENTS(frac0);
        if (shift > 0) {
            for ( int i = INDEX_LAST_DIG - shift; i >= 0; --i ) {
                values[i + shift] = values[i];
            }
            for ( int i = 0; i < shift; ++i )
            {
                values[i] = 0;
            }
        } else if (shift < 0) {
            for ( int i = -shift; i < NUM_TOTAL_DIG; ++i ) {
                values[i + shift] = values[i];
            }
            for ( int i = NUM_TOTAL_DIG + shift; i < NUM_TOTAL_DIG; ++i )
            {
                values[i] = 0;
            }
        }
        if (frac0 > p) {
            int cutPowersN = p > 0 ? (DIG_PER_INT32 - p) % DIG_PER_INT32 : -p;
            int cutInt = cutPowersN / DIG_PER_INT32;
            int cutPowers10 = cutPowersN % DIG_PER_INT32;
            if (cutInt) {
                int cutStartIndex = INDEX_LAST_DIG - (cutPowers10 ? 1 : 0);
                for (int i = cutStartIndex; i > cutStartIndex - cutInt; --i) {
                    values[i] = 0;
                }
            }
            if (cutPowers10) {
                values[INDEX_LAST_DIG] -= values[INDEX_LAST_DIG] % GetPowers10(cutPowers10);
            }
        }
        return *this;
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::CalcTruncTargetPrecision( int p ) {
        frac = p >= 0 ? aries_min(p, SUPPORTED_MAX_SCALE) : 0;
        if (-p >= intg) {
            intg = 1;
        }
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::CalcTruncatePrecision( int p ) {
        if (GET_CALC_INTG(mode) == 0 && GET_CALC_FRAC(error) == 0) {
            SET_CALC_INTG(mode, intg);
            SET_CALC_FRAC(error, frac);
        }
        uint16_t frac0 = p >= 0 ? aries_min(p, SUPPORTED_MAX_SCALE) : 0;
        uint16_t intg0 = GET_CALC_INTG(mode);
        if (-p >= intg0) {
            intg0 = 1;
        }
        uint8_t e = 0;
        FIX_INTG_FRAC_ERROR(SUPPORTED_MAX_PRECISION, intg0, frac0, e);
        SET_CALC_INTG(mode, intg0);
        SET_CALC_FRAC(error,frac0);
        SET_ERR(error, e);
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::CalcInnerTruncatePrecision( int p ) {
        uint16_t frac0 = p >= 0 ? aries_min(p, SUPPORTED_MAX_SCALE) : 0;
        uint16_t intg0 = intg;
        if (-p >= intg) {
            intg0 = 1;
        }
        uint16_t frac1, frac2;
        frac1 = frac2 = NEEDELEMENTS(frac0);
        uint16_t intg1, intg2;
        intg1 = intg2 = NEEDELEMENTS(intg0);
        uint8_t e = 0;
        FIX_INTG_FRAC_ERROR(INNER_MAX_PRECISION_INT32_NUM, intg1, frac1, e);
        SET_PREC_SCALE_VALUE(frac, frac0, frac1, frac2);
        SET_PREC_SCALE_VALUE(intg, intg0, intg1, intg2);
        SET_ERR(error, e);
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal::operator bool() const {
        return !isZero();
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal Decimal::operator-() {
        Decimal decimal(*this);
        #pragma unroll
        for (int i = 0; i < NUM_TOTAL_DIG; i++) {
            decimal.values[i] = -decimal.values[i];
        }
        return decimal;
    }

    //signed
    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator=(int8_t v) {
        Decimal tmp(v);
        SET_MODE(tmp.mode, GET_MODE(mode));
        *this = tmp;
        return *this;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator=(int16_t v) {
        Decimal tmp(v);
        SET_MODE(tmp.mode, GET_MODE(mode));
        *this = tmp;
        return *this;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator=(int32_t v) {
        Decimal tmp(v);
        SET_MODE(tmp.mode, GET_MODE(mode));
        *this = tmp;
        return *this;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator=(int64_t v) {
        Decimal tmp(v);
        SET_MODE(tmp.mode, GET_MODE(mode));
        *this = tmp;
        return *this;
    }

    //unsigned
    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator=(uint8_t v) {
        Decimal tmp(v);
        SET_MODE(tmp.mode, GET_MODE(mode));
        *this = tmp;
        return *this;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator=(uint16_t v) {
        Decimal tmp(v);
        SET_MODE(tmp.mode, GET_MODE(mode));
        *this = tmp;
        return *this;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator=(uint32_t v) {
        Decimal tmp(v);
        SET_MODE(tmp.mode, GET_MODE(mode));
        *this = tmp;
        return *this;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator=(uint64_t v) {
        Decimal tmp(v);
        SET_MODE(tmp.mode, GET_MODE(mode));
        *this = tmp;
        return *this;
    }

    //for decimal
    ARIES_HOST_DEVICE_NO_INLINE bool operator>(const Decimal &left, const Decimal &right) {
        int temp;
        if (ALIGNED(left.frac, right.frac)) {
            #pragma unroll
            for (int i = 0; i < NUM_TOTAL_DIG; i++) {
                if ((temp = (left.values[i] - right.values[i]))) {
                    return temp > 0;
                }
            }
        } else {
            Decimal l(left);
            Decimal r(right);
            l.AlignAddSubData(r);
            #pragma unroll
            for (int i = 0; i < NUM_TOTAL_DIG; i++) {
                if ((temp = (l.values[i] - r.values[i]))) {
                    return temp > 0;
                }
            }
        }
        return false;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>=(const Decimal &left, const Decimal &right) {
        return !(left < right);
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<(const Decimal &left, const Decimal &right) {
        int temp;
        if (ALIGNED(left.frac, right.frac)) {
            #pragma unroll
            for (int i = 0; i < NUM_TOTAL_DIG; i++) {
                if ((temp = (left.values[i] - right.values[i]))) {
                    return temp < 0;
                }
            }
        } else {
            Decimal l(left);
            Decimal r(right);
            l.AlignAddSubData(r);
            #pragma unroll
            for (int i = 0; i < NUM_TOTAL_DIG; i++) {
                if ((temp = (l.values[i] - r.values[i]))) {
                    return temp < 0;
                }
            }
        }
        return false;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<=(const Decimal &left, const Decimal &right) {
        return !(left > right);
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator==(const Decimal &left, const Decimal &right) {
        if (ALIGNED(left.frac, right.frac)) {
            for (int i = 0; i < NUM_TOTAL_DIG; i++) {
                if (left.values[i] - right.values[i]) {
                    return false;
                }
            }
        } else {
            Decimal l(left);
            Decimal r(right);
            l.AlignAddSubData(r);
            #pragma unroll
            for (int i = 0; i < NUM_TOTAL_DIG; i++) {
                if (l.values[i] - r.values[i]) {
                    return false;
                }
            }
        }
        return true;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator!=(const Decimal &left, const Decimal &right) {
        return !(left == right);
    }

    // for int8_t
    ARIES_HOST_DEVICE_NO_INLINE bool operator>(int8_t left, const Decimal &right) {
        return (int32_t) left > right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>=(int8_t left, const Decimal &right) {
        return (int32_t) left >= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<(int8_t left, const Decimal &right) {
        return (int32_t) left < right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<=(int8_t left, const Decimal &right) {
        return (int32_t) left <= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator==(int8_t left, const Decimal &right) {
        return (int32_t) left == right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator!=(int8_t left, const Decimal &right) {
        return !(left == right);
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>(const Decimal &left, int8_t right) {
        return left > (int32_t) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>=(const Decimal &left, int8_t right) {
        return left >= (int32_t) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<(const Decimal &left, int8_t right) {
        return left < (int32_t) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<=(const Decimal &left, int8_t right) {
        return left <= (int32_t) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator==(const Decimal &left, int8_t right) {
        return left == (int32_t) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator!=(const Decimal &left, int8_t right) {
        return left != (int32_t) right;
    }

    // for uint8_t
    ARIES_HOST_DEVICE_NO_INLINE bool operator>(uint8_t left, const Decimal &right) {
        return (uint32_t) left > right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>=(uint8_t left, const Decimal &right) {
        return (uint32_t) left >= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<(uint8_t left, const Decimal &right) {
        return (uint32_t) left < right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<=(uint8_t left, const Decimal &right) {
        return (uint32_t) left <= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator==(uint8_t left, const Decimal &right) {
        return (uint32_t) left == right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator!=(uint8_t left, const Decimal &right) {
        return !(left == right);
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>(const Decimal &left, uint8_t right) {
        return left > (uint32_t) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>=(const Decimal &left, uint8_t right) {
        return left >= (uint32_t) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<(const Decimal &left, uint8_t right) {
        return left < (uint32_t) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<=(const Decimal &left, uint8_t right) {
        return left <= (uint32_t) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator==(const Decimal &left, uint8_t right) {
        return left == (uint32_t) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator!=(const Decimal &left, uint8_t right) {
        return left != (uint32_t) right;
    }

    //for int16_t
    ARIES_HOST_DEVICE_NO_INLINE bool operator>(int16_t left, const Decimal &right) {
        return (int32_t) left > right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>=(int16_t left, const Decimal &right) {
        return (int32_t) left >= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<(int16_t left, const Decimal &right) {
        return (int32_t) left < right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<=(int16_t left, const Decimal &right) {
        return (int32_t) left <= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator==(int16_t left, const Decimal &right) {
        return (int32_t) left == right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator!=(int16_t left, const Decimal &right) {
        return (int32_t) left != right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>(const Decimal &left, int16_t right) {
        return left > (int32_t) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>=(const Decimal &left, int16_t right) {
        return left >= (int32_t) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<(const Decimal &left, int16_t right) {
        return left < (int32_t) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<=(const Decimal &left, int16_t right) {
        return left <= (int32_t) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator==(const Decimal &left, int16_t right) {
        return left == (int32_t) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator!=(const Decimal &left, int16_t right) {
        return left != (int32_t) right;
    }

    //for uint16_t
    ARIES_HOST_DEVICE_NO_INLINE bool operator>(uint16_t left, const Decimal &right) {
        return (uint32_t) left > right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>=(uint16_t left, const Decimal &right) {
        return (uint32_t) left >= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<(uint16_t left, const Decimal &right) {
        return (uint32_t) left < right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<=(uint16_t left, const Decimal &right) {
        return (uint32_t) left <= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator==(uint16_t left, const Decimal &right) {
        return (uint32_t) left == right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator!=(uint16_t left, const Decimal &right) {
        return (uint32_t) left != right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>(const Decimal &left, uint16_t right) {
        return left > (uint32_t) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>=(const Decimal &left, uint16_t right) {
        return left >= (uint32_t) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<(const Decimal &left, uint16_t right) {
        return left < (uint32_t) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<=(const Decimal &left, uint16_t right) {
        return left <= (uint32_t) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator==(const Decimal &left, uint16_t right) {
        return left == (uint32_t) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator!=(const Decimal &left, uint16_t right) {
        return left != (uint32_t) right;
    }

    //for int32_t
    ARIES_HOST_DEVICE_NO_INLINE bool operator>(int32_t left, const Decimal &right) {
        Decimal d(left);
        return d > right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>=(int32_t left, const Decimal &right) {
        Decimal d(left);
        return d >= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<(int32_t left, const Decimal &right) {
        Decimal d(left);
        return d < right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<=(int32_t left, const Decimal &right) {
        Decimal d(left);
        return d <= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator==(int32_t left, const Decimal &right) {
        Decimal d(left);
        return d == right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator!=(int32_t left, const Decimal &right) {
        Decimal d(left);
        return d != right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>(const Decimal &left, int32_t right) {
        Decimal d(right);
        return left > d;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>=(const Decimal &left, int32_t right) {
        Decimal d(right);
        return left >= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<(const Decimal &left, int32_t right) {
        Decimal d(right);
        return left < d;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<=(const Decimal &left, int32_t right) {
        Decimal d(right);
        return left <= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator==(const Decimal &left, int32_t right) {
        Decimal d(right);
        return left == d;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator!=(const Decimal &left, int32_t right) {
        Decimal d(right);
        return left != d;
    }

    //for uint32_t
    ARIES_HOST_DEVICE_NO_INLINE bool operator>(uint32_t left, const Decimal &right) {
        Decimal d(left);
        return d > right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>=(uint32_t left, const Decimal &right) {
        Decimal d(left);
        return d >= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<(uint32_t left, const Decimal &right) {
        Decimal d(left);
        return d < right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<=(uint32_t left, const Decimal &right) {
        Decimal d(left);
        return d <= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator==(uint32_t left, const Decimal &right) {
        Decimal d(left);
        return d == right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator!=(uint32_t left, const Decimal &right) {
        Decimal d(left);
        return d != right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>(const Decimal &left, uint32_t right) {
        Decimal d(right);
        return left > d;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>=(const Decimal &left, uint32_t right) {
        Decimal d(right);
        return left >= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<(const Decimal &left, uint32_t right) {
        Decimal d(right);
        return left < d;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<=(const Decimal &left, uint32_t right) {
        Decimal d(right);
        return left <= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator==(const Decimal &left, uint32_t right) {
        Decimal d(right);
        return left == d;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator!=(const Decimal &left, uint32_t right) {
        Decimal d(right);
        return left != d;
    }

    //for int64_t
    ARIES_HOST_DEVICE_NO_INLINE bool operator>(int64_t left, const Decimal &right) {
        Decimal d(left);
        return d > right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>=(int64_t left, const Decimal &right) {
        Decimal d(left);
        return d >= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<(int64_t left, const Decimal &right) {
        Decimal d(left);
        return d < right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<=(int64_t left, const Decimal &right) {
        Decimal d(left);
        return d <= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator==(int64_t left, const Decimal &right) {
        Decimal d(left);
        return d == right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator!=(int64_t left, const Decimal &right) {
        Decimal d(left);
        return d != right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>(const Decimal &left, int64_t right) {
        Decimal d(right);
        return left > d;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>=(const Decimal &left, int64_t right) {
        Decimal d(right);
        return left >= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<(const Decimal &left, int64_t right) {
        Decimal d(right);
        return left < d;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<=(const Decimal &left, int64_t right) {
        Decimal d(right);
        return left <= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator==(const Decimal &left, int64_t right) {
        Decimal d(right);
        return left == d;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator!=(const Decimal &left, int64_t right) {
        Decimal d(right);
        return left != d;
    }

    //for uint64_t
    ARIES_HOST_DEVICE_NO_INLINE bool operator>(uint64_t left, const Decimal &right) {
        Decimal d(left);
        return d > right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>=(uint64_t left, const Decimal &right) {
        Decimal d(left);
        return d >= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<(uint64_t left, const Decimal &right) {
        Decimal d(left);
        return d < right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<=(uint64_t left, const Decimal &right) {
        Decimal d(left);
        return d <= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator==(uint64_t left, const Decimal &right) {
        Decimal d(left);
        return d == right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator!=(uint64_t left, const Decimal &right) {
        Decimal d(left);
        return d != right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>(const Decimal &left, uint64_t right) {
        Decimal d(right);
        return left > d;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>=(const Decimal &left, uint64_t right) {
        Decimal d(right);
        return left >= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<(const Decimal &left, uint64_t right) {
        Decimal d(right);
        return left < d;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<=(const Decimal &left, uint64_t right) {
        Decimal d(right);
        return left <= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator==(const Decimal &left, uint64_t right) {
        Decimal d(right);
        return left == d;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator!=(const Decimal &left, uint64_t right) {
        Decimal d(right);
        return left != d;
    }

    //for float
    ARIES_HOST_DEVICE_NO_INLINE bool operator>(float left, const Decimal &right) {
        return (double) left > right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>=(float left, const Decimal &right) {
        return (double) left >= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<(float left, const Decimal &right) {
        return (double) left < right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<=(float left, const Decimal &right) {
        return (double) left <= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator==(float left, const Decimal &right) {
        return (double) left == right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator!=(float left, const Decimal &right) {
        return (double) left != right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>(const Decimal &left, float right) {
        return left > (double) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>=(const Decimal &left, float right) {
        return left >= (double) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<(const Decimal &left, float right) {
        return left < (double) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<=(const Decimal &left, float right) {
        return left <= (double) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator==(const Decimal &left, float right) {
        return left == (double) right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator!=(const Decimal &left, float right) {
        return left != (double) right;
    }

    //for double
    ARIES_HOST_DEVICE_NO_INLINE bool operator>(double left, const Decimal &right) {
        return left > right.GetDouble();
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>=(double left, const Decimal &right) {
        return left >= right.GetDouble();
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<(double left, const Decimal &right) {
        return left < right.GetDouble();
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<=(double left, const Decimal &right) {
        return left <= right.GetDouble();
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator==(double left, const Decimal &right) {
        return left == right.GetDouble();
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator!=(double left, const Decimal &right) {
        return left != right.GetDouble();
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>(const Decimal &left, double right) {
        return left.GetDouble() > right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator>=(const Decimal &left, double right) {
        return left.GetDouble() >= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<(const Decimal &left, double right) {
        return left.GetDouble() < right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator<=(const Decimal &left, double right) {
        return left.GetDouble() <= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator==(const Decimal &left, double right) {
        return left.GetDouble() == right;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool operator!=(const Decimal &left, double right) {
        return left.GetDouble() != right;
    }

    // for add
    ARIES_HOST_DEVICE_NO_INLINE void Decimal::CalcInnerAddPrecision(const Decimal& d) {
        uint16_t frac0 = aries_min(aries_max(frac, d.frac), SUPPORTED_MAX_SCALE);
        uint16_t intg0 = aries_max(intg, d.intg);
        int highestV1, highestV2, i1 = GetRealIntgSize(highestV1), i2 = d.GetRealIntgSize(highestV2);
        if (aries_max(i1, i2) >= NEEDELEMENTS(intg0)) {
            int value = i1 > i2 ? highestV1 : i1 < i2 ? highestV2 : highestV1 + highestV2;
            int maxIntg = intg0 % DIG_PER_INT32;
            if (maxIntg == 0) {
                maxIntg = DIG_PER_INT32;
            }
            if (value && (aries_abs(value) >= GetPowers10(maxIntg) - 1)) {
                intg0 += 1;
            }
        }
        uint16_t frac1, frac2;
        frac1 = frac2 = NEEDELEMENTS(frac0);
        uint16_t intg1, intg2;
        intg1 = intg2 = NEEDELEMENTS(intg0);
        uint8_t e = 0;
        FIX_INTG_FRAC_ERROR(INNER_MAX_PRECISION_INT32_NUM, intg1, frac1, e);
        SET_PREC_SCALE_VALUE(frac, frac0, frac1, frac2);
        SET_PREC_SCALE_VALUE(intg, intg0, intg1, intg2);
        SET_ERR(error, e);
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::CalcAddPrecision(const Decimal &d) {
        uint16_t frac0 = aries_min(aries_max(GET_CALC_FRAC(error), GET_CALC_FRAC(d.error)), SUPPORTED_MAX_SCALE);
        uint16_t intg0 = aries_max(GET_CALC_INTG(mode), GET_CALC_INTG(d.mode));
        int highestV1, highestV2, i1 = GetRealIntgSize(highestV1), i2 = d.GetRealIntgSize(highestV2);
        if (aries_max(i1, i2) >= NEEDELEMENTS(intg0)) {
            int value = i1 > i2 ? highestV1 : i1 < i2 ? highestV2 : highestV1 + highestV2;
            int maxIntg = intg0 % DIG_PER_INT32;
            if (maxIntg == 0) {
                maxIntg = DIG_PER_INT32;
            }
            if (value && (aries_abs(value) >= GetPowers10(maxIntg) - 1)) {
                intg0 += 1;
            }
        }
        uint8_t e = 0;
        FIX_INTG_FRAC_ERROR(SUPPORTED_MAX_PRECISION, intg0, frac0, e);
        SET_CALC_INTG(mode, intg0);
        SET_CALC_FRAC(error,frac0);
        SET_ERR(error, e);
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::CalcAddTargetPrecision( const Decimal& d ) {
        uint16_t frac0 = aries_min(aries_max(frac, d.frac), SUPPORTED_MAX_SCALE);
        uint16_t intg0 = aries_max(intg, d.intg) + 1;
        uint8_t e = 0;
        FIX_TAGET_INTG_FRAC_ERROR(SUPPORTED_MAX_PRECISION, intg0, frac0, e);
        intg = intg0;
        frac = frac0;
        error = e;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::AddBothPositiveNums(Decimal &d) {
        AlignAddSubData(d);
        //add
        int32_t carry = 0;
        for (int i = INDEX_LAST_DIG; i >= 0; i--) {
            values[i] += d.values[i];
            values[i] += carry;
            if (values[i] >= PER_DEC_MAX_SCALE) {
                carry = 1;
                values[i] -= PER_DEC_MAX_SCALE;
            } else {
                carry = 0;
            }
        }
        //        CheckOverFlow();
        return *this;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator+=(const Decimal &d) {
        CheckAndSetCalcPrecision();
        Decimal added(d);
        added.CheckAndSetCalcPrecision();
        //calculate precision after plus
        uint8_t intg0, frac0, mode0, error0;
        if (1 > 0) {
            Decimal calcPrecision(*this);
            calcPrecision.CalcAddPrecision(added);
            calcPrecision.CalcInnerAddPrecision(added);
            intg0 = calcPrecision.intg;
            frac0 = calcPrecision.frac;
            mode0 = calcPrecision.mode;
            error0 = calcPrecision.error;
        }
        bool addedNeg = added.isLessZero();
        if (isLessZero())  //-
        {
            Negate();
            if (addedNeg)  // --
            {
                //-a + -b = - (a + b)
                added.Negate();
                AddBothPositiveNums(added);
            } else //-+
            {
                //-a + b = - (a - b)
                SubBothPositiveNums(added);
            }
            Negate();
        } else {
            if (addedNeg) //+ -
            {
                // a + -b = a - (-b)
                added.Negate();
                SubBothPositiveNums(added);
            } else {
                AddBothPositiveNums(added);
            }
        }
        //set precision
        intg = intg0;
        frac = frac0;
        mode = mode0;
        error = error0;
        return *this;
    }

    //signed
    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator+=(int8_t i) {
        Decimal d(i);
        return *this += d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator+=(int16_t i) {
        Decimal d(i);
        return *this += d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator+=(int32_t i) {
        Decimal d(i);
        return *this += d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator+=(int64_t i) {
        Decimal d(i);
        return *this += d;
    }

    //unsigned
    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator+=(uint8_t i) {
        Decimal d(i);
        return *this += d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator+=(uint16_t i) {
        Decimal d(i);
        return *this += d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator+=(uint32_t i) {
        Decimal d(i);
        return *this += d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator+=(uint64_t i) {
        Decimal d(i);
        return *this += d;
    }

    //double / float
    ARIES_HOST_DEVICE_NO_INLINE double Decimal::operator+=(const float &f) {
        return *this += (double) f;
    }

    ARIES_HOST_DEVICE_NO_INLINE double Decimal::operator+=(const double &l) {
        return GetDouble() + l;
    }

    //self operator
    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator++() {
        Decimal d((int8_t) 1);
        *this += d;
        return *this;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal Decimal::operator++(int32_t) {
        Decimal d((int8_t) 1);
        *this += d;
        return *this;
    }

    //signed
    ARIES_HOST_DEVICE_NO_INLINE Decimal operator+(const Decimal &left, const Decimal &right) {
        Decimal tmp(left);
        return tmp += right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator+(const Decimal &left, int8_t right) {
        Decimal tmp(left);
        return tmp += right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator+(const Decimal &left, int16_t right) {
        Decimal tmp(left);
        return tmp += right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator+(const Decimal &left, int32_t right) {
        Decimal tmp(left);
        return tmp += right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator+(const Decimal &left, int64_t right) {
        Decimal tmp(left);
        return tmp += right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator+(int8_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp += right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator+(int16_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp += right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator+(int32_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp += right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator+(int64_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp += right;
    }

    //unsigned
    ARIES_HOST_DEVICE_NO_INLINE Decimal operator+(const Decimal &left, uint8_t right) {
        Decimal tmp(left);
        return tmp += right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator+(const Decimal &left, uint16_t right) {
        Decimal tmp(left);
        return tmp += right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator+(const Decimal &left, uint32_t right) {
        Decimal tmp(left);
        return tmp += right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator+(const Decimal &left, uint64_t right) {
        Decimal tmp(left);
        return tmp += right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator+(uint8_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp += right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator+(uint16_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp += right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator+(uint32_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp += right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator+(uint64_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp += right;
    }

    //double / float
    ARIES_HOST_DEVICE_NO_INLINE double operator+(const Decimal &left, float right) {
        return left.GetDouble() + right;
    }

    ARIES_HOST_DEVICE_NO_INLINE double operator+(const Decimal &left, double right) {
        return left.GetDouble() + right;
    }

    ARIES_HOST_DEVICE_NO_INLINE double operator+(float left, const Decimal &right) {
        return left + right.GetDouble();
    }

    ARIES_HOST_DEVICE_NO_INLINE double operator+(double left, const Decimal &right) {
        return left + right.GetDouble();
    }

    // for sub
    ARIES_HOST_DEVICE_NO_INLINE void Decimal::CalcSubPrecision(const Decimal &d) {
        CalcAddPrecision(d);
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::CalcSubTargetPrecision(const Decimal &d) {
        CalcAddTargetPrecision(d);
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::CalcInnerSubPrecision( const Decimal &d ) {
        CalcInnerAddPrecision(d);
    }

    // op1 and op2 are positive
    ARIES_HOST_DEVICE_NO_INLINE int32_t Decimal::CompareInt(int32_t *op1, int32_t *op2) {
        int32_t res = 0;
        #pragma unroll
        for (int i = 0; i < NUM_TOTAL_DIG && res == 0; i++) {
            res = op1[i] - op2[i];
        }
        return res;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::SubBothPositiveNums(Decimal &d) {
        int sign = 1;
        int32_t *p1 = (int32_t *) values, *p2 = (int32_t *) d.values;
        AlignAddSubData(d);
        int32_t r = CompareInt(p1, p2);
        if (r == 0) {
            #pragma unroll
            for (int i = 0; i < NUM_TOTAL_DIG; i++) {
                values[i] = 0;
            }
            return *this;
        } else if (r < 0) {
            int32_t *tmp;
            tmp = p1;
            p1 = p2;
            p2 = tmp;
            sign = -1;
        }
        //sub
        int32_t carry = 0; //借位
        for (int i = INDEX_LAST_DIG; i >= 0; i--) {
            p1[i] -= p2[i];
            p1[i] -= carry;
            if (p1[i] < 0) {
                p1[i] += PER_DEC_MAX_SCALE;
                carry = 1;
            } else {
                carry = 0;
            }
        }
        if (p1 != values) {
            #pragma unroll
            for (int i = 0; i < NUM_TOTAL_DIG; i++) {
                values[i] = p1[i];
            }
        }
        if (sign == -1) {
            Negate();
        }
        return *this;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator-=(const Decimal &d) {
        CheckAndSetCalcPrecision();
        Decimal subd(d);
        subd.CheckAndSetCalcPrecision();
        //calculate precision after plus
        uint8_t intg0, frac0, mode0, error0;
        if (1 > 0) {
            Decimal calcPrecision(*this);
            calcPrecision.CalcAddPrecision(subd);
            calcPrecision.CalcInnerAddPrecision(subd);
            intg0 = calcPrecision.intg;
            frac0 = calcPrecision.frac;
            mode0 = calcPrecision.mode;
            error0 = calcPrecision.error;
        }
        bool subdNeg = subd.isLessZero();
        //
        if (isLessZero())   //被减数为负数
        {
            Negate();
            if (subdNeg) //减数为负数
            {
                // -a - -b = b - a = - (a - b)
                subd.Negate();
                SubBothPositiveNums(subd);
            } else //减数为正数
            {
                //-a - b = - (a + b)
                AddBothPositiveNums(subd);
            }
            Negate();
        } else   //被减数为正数
        {
            if (subdNeg) //减数为负数
            {
                //a - -b = a + b
                subd.Negate();
                AddBothPositiveNums(subd);
            } else {
                SubBothPositiveNums(subd);
            }
        }
        //set precision
        intg = intg0;
        frac = frac0;
        mode = mode0;
        error = error0;
        return *this;
    }

    //signed
    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator-=(int8_t i) {
        Decimal d(i);
        return *this -= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator-=(int16_t i) {
        Decimal d(i);
        return *this -= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator-=(int32_t i) {
        Decimal d(i);
        return *this -= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator-=(int64_t i) {
        Decimal d(i);
        return *this -= d;
    }

    //unsigned
    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator-=(uint8_t i) {
        Decimal d(i);
        return *this -= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator-=(uint16_t i) {
        Decimal d(i);
        return *this -= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator-=(uint32_t i) {
        Decimal d(i);
        return *this -= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator-=(uint64_t i) {
        Decimal d(i);
        return *this -= d;
    }

    //double / float
    ARIES_HOST_DEVICE_NO_INLINE double Decimal::operator-=(const float &f) {
        return GetDouble() - f;
    }

    ARIES_HOST_DEVICE_NO_INLINE double Decimal::operator-=(const double &l) {
        return GetDouble() - l;
    }

    //self operator
    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator--() {
        Decimal d((int8_t) 1);
        return *this -= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal Decimal::operator--(int32_t) {
        Decimal tmp(*this);
        Decimal d((int8_t) 1);
        return tmp -= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator-(const Decimal &left, const Decimal &right) {
        Decimal tmp(left);
        return tmp -= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator-(const Decimal &left, int8_t right) {
        Decimal tmp(left);
        return tmp -= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator-(const Decimal &left, int16_t right) {
        Decimal tmp(left);
        return tmp -= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator-(const Decimal &left, int32_t right) {
        Decimal tmp(left);
        return tmp -= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator-(const Decimal &left, int64_t right) {
        Decimal tmp(left);
        return tmp -= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator-(int8_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp -= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator-(int16_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp -= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator-(int32_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp -= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator-(int64_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp -= right;
    }

    //unsigned
    ARIES_HOST_DEVICE_NO_INLINE Decimal operator-(const Decimal &left, uint8_t right) {
        Decimal tmp(left);
        return tmp -= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator-(const Decimal &left, uint16_t right) {
        Decimal tmp(left);
        return tmp -= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator-(const Decimal &left, uint32_t right) {
        Decimal tmp(left);
        return tmp -= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator-(const Decimal &left, uint64_t right) {
        Decimal tmp(left);
        return tmp -= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator-(uint8_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp -= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator-(uint16_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp -= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator-(uint32_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp -= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator-(uint64_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp -= right;
    }

    //double / float
    ARIES_HOST_DEVICE_NO_INLINE double operator-(const Decimal &left, const float right) {
        return left.GetDouble() - right;
    }

    ARIES_HOST_DEVICE_NO_INLINE double operator-(const Decimal &left, const double right) {
        return left.GetDouble() - right;
    }

    ARIES_HOST_DEVICE_NO_INLINE double operator-(const float left, const Decimal &right) {
        return left - right.GetDouble();
    }

    ARIES_HOST_DEVICE_NO_INLINE double operator-(const double left, const Decimal &right) {
        return left - right.GetDouble();
    }

    // for multiple
    ARIES_HOST_DEVICE_NO_INLINE void Decimal::CalcInnerMulPrecision(const Decimal& d) {
        uint16_t frac0 = aries_min(frac + d.frac, SUPPORTED_MAX_SCALE);
        uint16_t frac1, frac2;
        frac1 = frac2 = NEEDELEMENTS(frac0);
        uint16_t intg0 = intg + d.intg;
        uint16_t intg1, intg2;
        intg1 = intg2 = NEEDELEMENTS(intg0);
        uint8_t e = 0;
        FIX_INTG_FRAC_ERROR(INNER_MAX_PRECISION_INT32_NUM, intg1, frac1, e);
        SET_PREC_SCALE_VALUE(frac, frac0, frac1, frac2);
        SET_PREC_SCALE_VALUE(intg, intg0, intg1, intg2);
        SET_ERR(error, e);
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::CalcMulPrecision(const Decimal &d) {
        uint16_t frac0 = aries_min(GET_CALC_FRAC(error) + GET_CALC_FRAC(d.error), SUPPORTED_MAX_SCALE);
        uint16_t intg0 = GET_CALC_INTG(mode) + GET_CALC_INTG(d.mode);
        uint8_t e = 0;
        FIX_INTG_FRAC_ERROR(SUPPORTED_MAX_PRECISION, intg0, frac0, e);
        SET_CALC_INTG(mode, intg0);
        SET_CALC_FRAC(error,frac0);
        SET_ERR(error, e);
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::CalcMulTargetPrecision(const Decimal &d) {
        uint16_t frac0 = aries_min(frac + d.frac, SUPPORTED_MAX_SCALE);
        uint16_t intg0 = intg + d.intg;
        uint8_t e = 0;
        FIX_TAGET_INTG_FRAC_ERROR(SUPPORTED_MAX_PRECISION, intg0, frac0, e);
        intg = intg0;
        frac = frac0;
        error = e;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator*=(const Decimal &d) {
        int sign = 1;
        CheckAndSetCalcPrecision();
        Decimal other(d);
        other.CheckAndSetCalcPrecision();
        if (isLessZero()) {
            sign = -sign;
            Negate();
        }
        if (other.isLessZero()) {
            sign = -sign;
            other.Negate();
        }
        int8_t cutFrac = NEEDELEMENTS(frac) + NEEDELEMENTS(d.frac);
        //calculate precision after multiple
        CalcMulPrecision(other);
        CalcInnerMulPrecision(other);
        cutFrac -= NEEDELEMENTS(frac);
        //swap values
        for ( int k = 0; k <= INDEX_LAST_DIG / 2; ++k ) {
            int32_t v = values[k];
            values[k] = values[INDEX_LAST_DIG - k];
            values[INDEX_LAST_DIG - k] = v;
            v = other.values[k];
            other.values[k] = other.values[INDEX_LAST_DIG - k];
            other.values[INDEX_LAST_DIG - k] = v;
        }
        int32_t res[NUM_TOTAL_DIG * 2] = {0};
        int32_t *op1 = values, *op2 = other.values;
        //multiple
        int32_t carry = 0;
        int64_t temp = 0;
        for (int i = 0; i < NUM_TOTAL_DIG; i++) {
            if (op2[i] == 0) {
                continue;
            }
            carry = 0;
            int32_t resIndex = 0;
            #pragma unroll
            for (int j = 0; j < NUM_TOTAL_DIG; j++) {
                resIndex = i + j;
                if (op1[j] || carry) {
                    if (op1[j]) {
                        temp = (int64_t) op1[j] * op2[i];
                    }
                    temp += res[resIndex] + carry;
                    if (temp >= PER_DEC_MAX_SCALE) {
                        carry = temp / PER_DEC_MAX_SCALE;
                        res[resIndex] = temp % PER_DEC_MAX_SCALE;
                    } else {
                        res[resIndex] = temp;
                        carry = 0;
                    }
                    temp = 0;
                }
            }
        }
        #pragma unroll
        for (int i = 0; i < NUM_TOTAL_DIG; i++) {
            values[INDEX_LAST_DIG - i] = res[i + cutFrac];
        }
        if (sign == -1) {
            Negate();
        }
        return *this;
    }

    //signed
    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator*=(int8_t i) {
        Decimal tmp(i);
        return *this *= tmp;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator*=(int16_t i) {
        Decimal tmp(i);
        return *this *= tmp;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator*=(int32_t i) {
        Decimal tmp(i);
        return *this *= tmp;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator*=(int64_t i) {
        Decimal tmp(i);
        return *this *= tmp;
    }

    //unsigned
    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator*=(uint8_t i) {
        Decimal tmp(i);
        return *this *= tmp;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator*=(uint16_t i) {
        Decimal tmp(i);
        return *this *= tmp;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator*=(uint32_t i) {
        Decimal tmp(i);
        return *this *= tmp;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator*=(uint64_t i) {
        Decimal tmp(i);
        return *this *= tmp;
    }

    //double / float
    ARIES_HOST_DEVICE_NO_INLINE double Decimal::operator*=(const float &f) {
        return GetDouble() * f;
    }

    ARIES_HOST_DEVICE_NO_INLINE double Decimal::operator*=(const double &d) {
        return GetDouble() * d;
    }

    //two operators
    ARIES_HOST_DEVICE_NO_INLINE Decimal operator*(const Decimal &left, const Decimal &right) {
        Decimal tmp(left);
        return tmp *= right;
    }

    //signed
    ARIES_HOST_DEVICE_NO_INLINE Decimal operator*(const Decimal &left, int8_t right) {
        Decimal tmp(right);
        return tmp *= left;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator*(const Decimal &left, int16_t right) {
        Decimal tmp(right);
        return tmp *= left;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator*(const Decimal &left, int32_t right) {
        Decimal tmp(right);
        return tmp *= left;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator*(const Decimal &left, int64_t right) {
        Decimal tmp(right);
        return tmp *= left;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator*(int8_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp *= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator*(int16_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp *= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator*(int32_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp *= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator*(int64_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp *= right;
    }

    //unsigned
    ARIES_HOST_DEVICE_NO_INLINE Decimal operator*(const Decimal &left, uint8_t right) {
        Decimal tmp(right);
        return tmp *= left;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator*(const Decimal &left, uint16_t right) {
        Decimal tmp(right);
        return tmp *= left;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator*(const Decimal &left, uint32_t right) {
        Decimal tmp(right);
        return tmp *= left;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator*(const Decimal &left, uint64_t right) {
        Decimal tmp(right);
        return tmp *= left;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator*(uint8_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp *= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator*(uint16_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp *= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator*(uint32_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp *= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator*(uint64_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp *= right;
    }

    //double / float
    ARIES_HOST_DEVICE_NO_INLINE double operator*(const Decimal &left, const float right) {
        return left.GetDouble() * right;
    }

    ARIES_HOST_DEVICE_NO_INLINE double operator*(const Decimal &left, const double right) {
        return left.GetDouble() * right;
    }

    ARIES_HOST_DEVICE_NO_INLINE double operator*(const float left, const Decimal &right) {
        return left * right.GetDouble();
    }

    ARIES_HOST_DEVICE_NO_INLINE double operator*(const double left, const Decimal &right) {
        return left * right.GetDouble();
    }

    // for division
    ARIES_HOST_DEVICE_NO_INLINE void Decimal::CalcInnerDivPrecision(const Decimal& d) {
        uint16_t frac0 = aries_min(frac + DIV_FIX_INNER_FRAC, SUPPORTED_MAX_SCALE);
        int highestV1, highestV2, prec1 = GetRealPrecision(highestV1), prec2 = d.GetRealPrecision(highestV2);
        int16_t intg0 = prec1 - frac - (prec2 - d.frac) + (highestV1 >= highestV2);
        if (intg0 < 0) {
            intg0 = 0;
        }
        uint16_t frac1, frac2;
        frac1 = frac2 = NEEDELEMENTS(frac0);
        uint16_t intg1, intg2;
        intg1 = intg2 = NEEDELEMENTS(intg0);
        uint8_t e = 0;
        FIX_INTG_FRAC_ERROR(INNER_MAX_PRECISION_INT32_NUM, intg1, frac1, e);
        SET_PREC_SCALE_VALUE(frac, frac0, frac1, frac2);
        SET_PREC_SCALE_VALUE(intg, intg0, intg1, intg2);
        SET_ERR(error, e);
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::CalcDivPrecision( const Decimal &d ) {
        uint16_t frac0 = aries_min(GET_CALC_FRAC(error) + DIV_FIX_EX_FRAC, SUPPORTED_MAX_SCALE);
        int highestV1, highestV2, prec1 = GetRealPrecision(highestV1), prec2 = d.GetRealPrecision(highestV2);
        int16_t intg0 = prec1 - GET_CALC_FRAC(error) - (prec2 - GET_CALC_FRAC(d.error)) + (highestV1 >= highestV2);
        if (intg0 < 0) {
            intg0 = 0;
        }
        uint8_t e = 0;
        FIX_INTG_FRAC_ERROR(SUPPORTED_MAX_PRECISION, intg0, frac0, e);
        SET_CALC_INTG(mode, intg0);
        SET_CALC_FRAC(error,frac0);
        SET_ERR(error, e);
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::CalcDivTargetPrecision( const Decimal &d ) {
        uint16_t frac0 = aries_min(frac + DIV_FIX_EX_FRAC, SUPPORTED_MAX_SCALE);
        uint16_t intg0 = aries_min(intg + d.frac, SUPPORTED_MAX_PRECISION);
        uint8_t e = 0;
        FIX_TAGET_INTG_FRAC_ERROR(SUPPORTED_MAX_PRECISION, intg0, frac0, e);
        intg = intg0;
        frac = frac0;
        error = e;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator>>(int n) {
        int shiftDigits = n % DIG_PER_INT32;
        int shiftInt = n / DIG_PER_INT32;
        if (shiftDigits) {
            int lower = GetPowers10(shiftDigits);
            int higher = GetPowers10( DIG_PER_INT32 - shiftDigits);
            int carry = 0, temp = 0;
            #pragma unroll
            for (int i = 0; i < NUM_TOTAL_DIG; i++) {
                if (values[i] != 0) {
                    temp = values[i] % lower;
                    values[i] = values[i] / lower;
                } else {
                    temp = 0;
                }
                if (carry) {
                    values[i] += carry * higher;
                }
                carry = temp;
            }
        }
        if (shiftInt) {
            for (int i = INDEX_LAST_DIG; i >= shiftInt; i--) {
                values[i] = values[i - shiftInt];
            }
            for (int i = 0; i < shiftInt; i++) {
                values[i] = 0;
            }
        }
        //for check
        for (int i = 0; i < shiftInt; i++) {
            assert(values[i] == 0);
        }
        if (shiftDigits) {
            int lower = GetPowers10(shiftDigits);
            assert(values[shiftInt] / lower == 0);
        }
        return *this;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator<<(int n) {
        int shiftDigits = n % DIG_PER_INT32;
        int shiftInt = n / DIG_PER_INT32;
        int lower = GetPowers10( DIG_PER_INT32 - shiftDigits);
        int higher = GetPowers10(shiftDigits);
        if (shiftDigits) {
            int carry = 0, temp = 0;
            for (int i = INDEX_LAST_DIG; i >= 0; i--) {
                if (values[i] != 0) {
                    temp = values[i] / lower;
                    values[i] = values[i] % lower * higher;
                } else {
                    temp = 0;
                }
                if (carry) {
                    values[i] += carry;
                }
                carry = temp;
            }
        }
        if (shiftInt) {
            for (int i = 0; i < NUM_TOTAL_DIG - shiftInt; i++) {
                values[i] = values[i + shiftInt];
            }
            for (int i = NUM_TOTAL_DIG - shiftInt; i < NUM_TOTAL_DIG; i++) {
                values[i] = 0;
            }
        }
        intg += n;
        return *this;
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::UpdateIntgDigits() {
        int validPos = 0;
        for ( validPos = 0; validPos < NUM_TOTAL_DIG; ++validPos )
        {
            if (values[validPos]) {
                break;
            }
        }
        int intg0 = NUM_TOTAL_DIG - validPos - NEEDELEMENTS(frac);
        if (intg0 <= 0) {
            intg = 0;
        } else {
            int v = aries_abs(values[validPos]);
            int digit = 1;
            while(v >= GetPowers10(digit) && ++digit < DIG_PER_INT32);
            intg = (intg0 - 1) * DIG_PER_INT32 + digit;
        }
    }

    ARIES_HOST_DEVICE_NO_INLINE int Decimal::GetRealPrecision(int &highestValue) const {
        int validPos = 0;
        for ( ; validPos < NUM_TOTAL_DIG; ++validPos )
        {
            if (values[validPos]) {
                break;
            }
        }
        int prec0 = NUM_TOTAL_DIG - validPos;
        if (prec0 <= 0) {
            highestValue = 0;
            return 0;
        }
        int v = aries_abs(values[validPos]);
        int digit = 1;
        while(v >= GetPowers10(digit) && ++digit < DIG_PER_INT32);
        highestValue = v / GetPowers10(digit - 1);
        if (frac == 0) {
            return digit + (prec0 - 1) * DIG_PER_INT32;
        } else {
            int lastFrac = frac % DIG_PER_INT32;
            return digit + (prec0 - 2) * DIG_PER_INT32 + (lastFrac == 0 ? DIG_PER_INT32 :  lastFrac);
        }
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::CheckAndSetCalcPrecision() {
        CheckAndSetRealPrecision();
        if (GET_CALC_FRAC(error) == 0 && GET_CALC_INTG(mode) == 0) {
            SET_CALC_FRAC(error, frac);
            SET_CALC_INTG(mode, intg);
        }
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::CheckAndSetRealPrecision() {
        int highest;
        int prec = GetRealPrecision(highest);
        intg = prec - frac;
        if ((intg & 0x80) > 0) {
            intg = 0;
        }
        if (intg == 0) {
            intg = 1;
        }
    }

    ARIES_HOST_DEVICE_NO_INLINE int Decimal::GetRealIntgSize(int &highestValue) const {
        int validPos = 0;
        for ( ; validPos < NUM_TOTAL_DIG; ++validPos )
        {
            if (values[validPos]) {
                break;
            }
        }
        int intg0 = NUM_TOTAL_DIG - validPos - NEEDELEMENTS(frac);
        if (intg0 <= 0) {
            highestValue = 0;
            intg0 = 0;
        } else {
            highestValue = values[validPos];
        }
        return intg0;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::GenIntDecimal(int shift) {
        int n = shift;
        if (frac) {
            n -= DIG_PER_INT32 - frac % DIG_PER_INT32;
        }
        if (n > 0) {
            *this << n;
        } else if (n < 0) {
            *this >> (-n);
        }
        frac = 0;
        UpdateIntgDigits();
        return *this;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal Decimal::HalfIntDecimal(const Decimal d1, const Decimal d2) {
        Decimal tmp(d1);
        tmp += d2;
        int32_t rds = 0;
        int64_t t[NUM_TOTAL_DIG];
        #pragma unroll
        for (int i = 0; i < NUM_TOTAL_DIG; i++) {
            t[i] = tmp.values[i];
        }
        #pragma unroll
        for (int i = 0; i < NUM_TOTAL_DIG; i++) {
            if (rds) {
                t[i] += rds * PER_DEC_MAX_SCALE;
            }
            if (t[i]) {
                rds = t[i] % 2;
                t[i] /= 2;
            }
        }
        #pragma unroll
        for (int i = 0; i < NUM_TOTAL_DIG; i++) {
            tmp.values[i] = t[i];
        }
        return tmp;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal Decimal::DivInt(const Decimal ds, const Decimal dt, Decimal &residuel) {
        if (ds.isZero()) {
            residuel = 0;
            return ds;
        }
        int q = ds.intg - dt.intg;
        Decimal qmax(q + 1, 0), qmin(q, 0), qmid, rsdmax, rsdmin, rsdtmp;
        qmax.GenMaxDecByPrecision();
        qmin.GenMinDecByPrecision();
        Decimal t = qmax * dt;
        rsdmax = ds - t;
        if (rsdmax >= 0) {
            residuel = rsdmax;
            return qmax;
        }
        rsdmin = ds - qmin * dt;
        if (rsdmin == 0) {
            residuel = 0;
            return qmin;
        }
        assert(rsdmin > 0);
        while (qmin < qmax) {
            qmid = HalfIntDecimal(qmax, qmin);
            if (qmid == qmin) {
                break;
            }
            rsdtmp = ds - qmid * dt;
            if (rsdtmp == 0) {
                rsdmin = 0;
                qmin = qmid;
                break;
            } else if (rsdtmp > 0) {
                rsdmin = rsdtmp;
                qmin = qmid;
            } else {
                rsdmax = rsdtmp;
                qmax = qmid;
            }
        }
        residuel = rsdmin;
        return qmin;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal& Decimal::DivByInt(const Decimal &d, int shift, bool isMod) {
        int dvt = d.values[INDEX_LAST_DIG];
        int remainder = 0;
        *this << shift;
        #pragma unroll
        for (int i = 0; i < NUM_TOTAL_DIG; ++i) {
            if (values[i] || remainder) {
                int64_t tmp = (int64_t) values[i] + (int64_t) remainder * PER_DEC_MAX_SCALE;
                values[i] = tmp / dvt;
                remainder = tmp % dvt;
            }
        }
        if (isMod) {
            *this = remainder;
        } else if (remainder << 1 > dvt) {
            *this += 1;
        }
        return *this;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal& Decimal::DivByInt64(const Decimal &divisor, int shift, bool isMod) {
        int64_t dvs = ToInt64();
        while (shift > DIG_PER_INT32) {
            dvs *= GetPowers10(DIG_PER_INT32);
            shift -= DIG_PER_INT32;
        }
        dvs *= GetPowers10(shift);
        int64_t dvt = divisor.ToInt64();
        int64_t res = isMod ? (dvs % dvt) : (dvs / dvt + (((dvs % dvt) << 1) >= dvt ? 1 : 0));
        return *this = res;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::Negate() {
        #pragma unroll
        for (int i = 0; i < NUM_TOTAL_DIG; i++) {
            values[i] = -values[i];
        }
        return *this;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::IntToFrac(int fracDigits) {
        int frac0 = NEEDELEMENTS(fracDigits);

        Decimal intgPart(*this);
        intgPart >> (fracDigits);
        Decimal fracPart(*this);
        fracPart << ( DIG_PER_INT32 * NUM_TOTAL_DIG - fracDigits);
        for (int i = 0; i < NUM_TOTAL_DIG - frac0; i++) {
            values[i] = intgPart.values[i + frac0];
        }
        int fracBase = NUM_TOTAL_DIG - frac0;
        for (int i = fracBase; i < NUM_TOTAL_DIG; i++) {
            values[i] = fracPart.values[i - fracBase];
        }
        frac = fracDigits;
        UpdateIntgDigits();
        return *this;
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::CopyValue(Decimal &d) {
        #pragma unroll
        for (int i = 0; i < NUM_TOTAL_DIG; ++i) {
            values[i] = d.values[i];
        }
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal& Decimal::DivOrMod( const Decimal &d, bool isMod ) {
#ifdef COMPUTE_BY_STRING
        char divitend[128] =
        {   0};
        char divisor[128] =
        {   0};
        char result[128] =
        {   0};
        GetDivDecimalStr( divitend );
        Decimal tmpDt( d );
        tmpDt.GetDivDecimalStr( divisor );
        //multiple
        int len = aries_strlen( divitend );
        int end = len + d.frac + DIV_FIX_INNER_FRAC;
        for( int i = len; i < end; i++ )
        {
            divitend[i] = '0';
        }
        divitend[end] = 0;
        CalcDivPrecision( d );
        DivInt( divitend, divisor, 1, result );
        len = aries_strlen( result );
        assert( frac + intg >= len );
        if (len < frac)
        {
            for (int i = 0; i < frac -len; i++)
            {
                result[len + i] = '0';
            }
            result[frac] = 0;
            len = aries_strlen(result);
        }
        int p = len;
        InsertCh( result, len - frac, '.' );
        if (result[0] == '-')
        {
            p--;
        }
//        Decimal tmp( intg + frac, frac, result );
        Decimal tmp( p, frac, result );
        int err = error;
        *this = tmp;
        error = err;
#else
        CheckAndSetCalcPrecision();
        Decimal divitend(*this);
        Decimal divisor(d);
        divisor.CheckAndSetCalcPrecision();
        if (isMod)
        {
            CalcModPrecision(divisor);
            CalcInnerModPrecision(divisor);
        } else {
            CalcDivPrecision(divisor);
            CalcInnerDivPrecision(divisor);
        }
        if (isZero()) {
            return *this;
        } else if (d.isZero()) {
            SET_ERR(error, ERR_DIV_BY_ZERO);
            return *this;
        }

        uint8_t divitendFrac = divitend.frac;
        divitend.GenIntDecimal(isMod ? (divitendFrac < d.frac ? d.frac - divitendFrac : 0) : 0);
        int sign = 1;
        if (divitend.isLessZero()) {
            divitend.Negate();
            sign = -sign;
        }

        divisor.GenIntDecimal(isMod ? (d.frac < divitendFrac ? divitendFrac - d.frac : 0) : 0);
        if (divisor.isLessZero()) {
            sign = -sign;
            divisor.Negate();
        }
        int shift = d.frac + DIV_FIX_INNER_FRAC;
        if (!isMod) {
            // result is 0
            if (divitend.intg + shift < divisor.intg) {
                aries_memset(values, 0x00, sizeof(values));
                return *this;
            }
        } else {
            shift = 0;
        }

        Decimal res;
        //check if use integer div operator directly
        if (divitend.intg + shift <= DIG_PER_INT64 && divisor.intg <= DIG_PER_INT64) {
            res = divitend.DivByInt64(divisor, shift, isMod);
        } else if (divisor.intg <= DIG_PER_INT32) {
            res = divitend.DivByInt(divisor, shift, isMod);
        } else {
            int tmpEx = shift;
            int nDigits = 0;
            //one step DIG_PER_INT32 digit left
            Decimal tmpRes;
            if(shift == 0 && isMod){
                divitend.UpdateIntgDigits();
                nDigits = INNER_MAX_PRECISION - divitend.intg - 1;
                if (nDigits > tmpEx) {
                    nDigits = tmpEx;
                }
                tmpEx -= nDigits;
                divitend << (nDigits);
                tmpRes = DivInt(divitend, divisor, divitend);
                if (res != 0) {
                    res *= GetPowers10(nDigits);
                }
                res += tmpRes;
            }
            else{
                for (; tmpEx > 0;) {
                    divitend.UpdateIntgDigits();
                    nDigits = INNER_MAX_PRECISION - divitend.intg - 1;
                    if (nDigits > tmpEx) {
                        nDigits = tmpEx;
                    }
                    tmpEx -= nDigits;
                    divitend << (nDigits);
                    tmpRes = DivInt(divitend, divisor, divitend);
                    if (res != 0) {
                        res *= GetPowers10(nDigits);
                    }
                    res += tmpRes;
                }
            }
            //check if need round up
            if (isMod) {
                res = divitend;
            } else {
                if (divitend + divitend >= divisor) {
                    res += 1;
                }
            }
        }
        CopyValue(res.IntToFrac(frac));
        if (sign == -1) {
            Negate();
        }
#endif
        return *this;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator/=(const Decimal &d) {
        return DivOrMod(d);
    }

    //signed
    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator/=(int8_t i) {
        Decimal d(i);
        return *this /= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator/=(int16_t i) {
        Decimal d(i);
        return *this /= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator/=(int32_t i) {
        Decimal d(i);
        return *this /= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator/=(int64_t i) {
        Decimal d(i);
        return *this /= d;
    }

    //unsigned
    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator/=(uint8_t i) {
        Decimal d(i);
        return *this /= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator/=(uint16_t i) {
        Decimal d(i);
        return *this /= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator/=(uint32_t i) {
        Decimal d(i);
        return *this /= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator/=(uint64_t i) {
        Decimal d(i);
        return *this /= d;
    }

    //double / float
    ARIES_HOST_DEVICE_NO_INLINE double Decimal::operator/=(const float &f) {
        return GetDouble() / f;
    }

    ARIES_HOST_DEVICE_NO_INLINE double Decimal::operator/=(const double &d) {
        return GetDouble() / d;
    }

    //two operators
    ARIES_HOST_DEVICE_NO_INLINE Decimal operator/(const Decimal &left, const Decimal &right) {
        Decimal tmp(left);
        return tmp /= right;
    }

    //signed
    ARIES_HOST_DEVICE_NO_INLINE Decimal operator/(const Decimal &left, int8_t right) {
        Decimal tmp(left);
        return tmp /= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator/(const Decimal &left, int16_t right) {
        Decimal tmp(left);
        return tmp /= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator/(const Decimal &left, int32_t right) {
        Decimal tmp(left);
        return tmp /= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator/(const Decimal &left, int64_t right) {
        Decimal tmp(left);
        return tmp /= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator/(int8_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp /= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator/(int16_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp /= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator/(int32_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp /= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator/(int64_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp /= right;
    }

    //unsigned
    ARIES_HOST_DEVICE_NO_INLINE Decimal operator/(const Decimal &left, uint8_t right) {
        Decimal tmp(left);
        return tmp /= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator/(const Decimal &left, uint16_t right) {
        Decimal tmp(left);
        return tmp /= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator/(const Decimal &left, uint32_t right) {
        Decimal tmp(left);
        return tmp /= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator/(const Decimal &left, uint64_t right) {
        Decimal tmp(left);
        return tmp /= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator/(uint8_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp /= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator/(uint16_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp /= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator/(uint32_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp /= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator/(uint64_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp /= right;
    }

    //double / float
    ARIES_HOST_DEVICE_NO_INLINE double operator/(const Decimal &left, const float right) {
        return left.GetDouble() / right;
    }

    ARIES_HOST_DEVICE_NO_INLINE double operator/(const Decimal &left, const double right) {
        return left.GetDouble() / right;
    }

    ARIES_HOST_DEVICE_NO_INLINE double operator/(const float left, const Decimal &right) {
        return left / right.GetDouble();
    }

    ARIES_HOST_DEVICE_NO_INLINE double operator/(const double left, const Decimal &right) {
        return left / right.GetDouble();
    }

    // for mod
    ARIES_HOST_DEVICE_NO_INLINE void Decimal::CalcModPrecision( const Decimal &d ) {
        int i = 0;
        uint8_t frac0 = GET_CALC_FRAC(error), frac1 = GET_CALC_FRAC(d.error), intg0;
        if (frac0 < frac1) {
            frac0 = frac1;
        } else {
            i = frac0 - frac1;
        }
        intg0 = GET_CALC_INTG(d.mode) + i;
        SET_CALC_INTG(mode, intg0);
        SET_CALC_FRAC(error, frac0);
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::CalcModTargetPrecision( const Decimal &d ) {
        int i = 0;
        uint8_t frac0 = frac, frac1 = d.frac, intg0;
        if (frac0 < frac1) {
            frac0 = frac1;
        } else {
            i = frac0 - frac1;
        }
        intg0 = d.intg + i;
        uint8_t e;
        FIX_TAGET_INTG_FRAC_ERROR(SUPPORTED_MAX_PRECISION, intg0, frac0, e);
        intg = intg0;
        frac = frac0;
        error = e;
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::CalcInnerModPrecision( const Decimal &d ) {
        int i = 0;
        if (frac < d.frac) {
            frac = d.frac;
        } else {
            i = frac - d.frac;
        }
        intg = d.intg + i;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator%=(const Decimal& d) {
        return DivOrMod(d, true);
    }
    //signed
    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator%=(int8_t i) {
        Decimal d(i);
        return *this %= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator%=(int16_t i) {
        Decimal d(i);
        return *this %= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator%=(int32_t i) {
        Decimal d(i);
        return *this %= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator%=(int64_t i) {
        Decimal d(i);
        return *this %= d;
    }

    //unsigned
    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator%=(uint8_t i) {
        Decimal d(i);
        return *this %= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator%=(uint16_t i) {
        Decimal d(i);
        return *this %= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator%=(uint32_t i) {
        Decimal d(i);
        return *this %= d;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal &Decimal::operator%=(uint64_t i) {
        Decimal d(i);
        return *this %= d;
    }

    //double % float
    ARIES_HOST_DEVICE_NO_INLINE double Decimal::operator%=(const float &f) {
        return fmod(GetDouble(), f);
    }

    ARIES_HOST_DEVICE_NO_INLINE double Decimal::operator%=(const double &d) {
        return fmod(GetDouble(), d);
    }

    //two operators
    ARIES_HOST_DEVICE_NO_INLINE Decimal operator%(const Decimal &left, const Decimal &right) {
        Decimal tmp(left);
        return tmp %= right;
    }

    //signed
    ARIES_HOST_DEVICE_NO_INLINE Decimal operator%(const Decimal &left, int8_t right) {
        Decimal tmp(left);
        return tmp %= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator%(const Decimal &left, int16_t right) {
        Decimal tmp(left);
        return tmp %= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator%(const Decimal &left, int32_t right) {
        Decimal tmp(left);
        return tmp %= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator%(const Decimal &left, int64_t right) {
        Decimal tmp(left);
        return tmp %= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator%(int8_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp %= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator%(int16_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp %= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator%(int32_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp %= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator%(int64_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp %= right;
    }

    //unsigned
    ARIES_HOST_DEVICE_NO_INLINE Decimal operator%(const Decimal &left, uint8_t right) {
        Decimal tmp(left);
        return tmp %= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator%(const Decimal &left, uint16_t right) {
        Decimal tmp(left);
        return tmp %= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator%(const Decimal &left, uint32_t right) {
        Decimal tmp(left);
        return tmp %= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator%(const Decimal &left, uint64_t right) {
        Decimal tmp(left);
        return tmp %= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator%(uint8_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp %= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator%(uint16_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp %= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator%(uint32_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp %= right;
    }

    ARIES_HOST_DEVICE_NO_INLINE Decimal operator%(uint64_t left, const Decimal &right) {
        Decimal tmp(left);
        return tmp %= right;
    }

    //double % float
    ARIES_HOST_DEVICE_NO_INLINE double operator%(const Decimal &left, const float right) {
        return fmod(left.GetDouble(), right);
    }

    ARIES_HOST_DEVICE_NO_INLINE double operator%(const Decimal &left, const double right) {
        return fmod(left.GetDouble(), right);
    }

    ARIES_HOST_DEVICE_NO_INLINE double operator%(const float left, const Decimal &right) {
        return fmod((double)left, right.GetDouble());
    }

    ARIES_HOST_DEVICE_NO_INLINE double operator%(const double left, const Decimal &right) {
        return fmod((double)left, right.GetDouble());
    }

    ARIES_HOST_DEVICE_NO_INLINE bool Decimal::isFracZero() const {
        for (int i = INDEX_LAST_DIG - NEEDELEMENTS(frac); i <= INDEX_LAST_DIG; ++i) {
            if (values[i]) {
                return false;
            }
        }
        return true;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool Decimal::isZero() const {
        for (int i = 0; i < NUM_TOTAL_DIG; ++i) {
            if (values[i] != 0) {
                return false;
            }
        }
        return true;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool Decimal::isLessZero() const {
        for (int i = 0; i < NUM_TOTAL_DIG; ++i) {
            if (values[i] < 0) {
                return true;
            }
        }
        return false;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool Decimal::isLessEqualZero() const {
        for (int i = 0; i < NUM_TOTAL_DIG; ++i) {
            if (values[i] > 0) {
                return false;
            }
        }
        return true;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool Decimal::isGreaterZero() const {
        for (int i = 0; i < NUM_TOTAL_DIG; ++i) {
            if (values[i] > 0) {
                return true;
            }
        }
        return false;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool Decimal::isGreaterEqualZero() const {
        for (int i = 0; i < NUM_TOTAL_DIG; ++i) {
            if (values[i] < 0) {
                return false;
            }
        }
        return true;
    }

    ARIES_HOST_DEVICE_NO_INLINE int32_t Decimal::GetPowers10(int i) const {
        int32_t res = 1;
        switch (i) {
            case 0:
                res = 1;
                break;
            case 1:
                res = 10;
                break;
            case 2:
                res = 100;
                break;
            case 3:
                res = 1000;
                break;
            case 4:
                res = 10000;
                break;
            case 5:
                res = 100000;
                break;
            case 6:
                res = 1000000;
                break;
            case 7:
                res = 10000000;
                break;
            case 8:
                res = 100000000;
                break;
            case 9:
                res = PER_DEC_MAX_SCALE;
                break;
            default:
                break;
        }
        return res;
    }

    ARIES_HOST_DEVICE_NO_INLINE int32_t Decimal::GetFracMaxTable(int i) const {
        int32_t res = 0;
        switch (i) {
            case 0:
                res = 900000000;
                break;
            case 1:
                res = 990000000;
                break;
            case 2:
                res = 999000000;
                break;
            case 3:
                res = 999900000;
                break;
            case 4:
                res = 999990000;
                break;
            case 5:
                res = 999999000;
                break;
            case 6:
                res = 999999900;
                break;
            case 7:
                res = 999999990;
                break;
            case 8:
                res = 999999999;
                break;
            default:
                break;
        }
        return res;
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::GenMaxDecByPrecision() {
        int index = NUM_TOTAL_DIG - NEEDELEMENTS(intg) - NEEDELEMENTS(frac);
        // clear no use values
        for (int i = 0; i < index; i++) {
            values[i] = 0;
        }
        int firstDigits = intg % DIG_PER_INT32;
        if (firstDigits) {
            values[index++] = GetPowers10(firstDigits) - 1;
        }
        int32_t overPerDec = PER_DEC_MAX_SCALE - 1;
        for (int i = index; i < NUM_TOTAL_DIG; i++) {
            values[i] = overPerDec;
        }
        //replace last frac if necessary
        if (frac) {
            int lastDigits = frac % DIG_PER_INT32;
            if (lastDigits) {
                values[INDEX_LAST_DIG] = GetFracMaxTable(lastDigits - 1);
            }
        }
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::GenMinDecByPrecision() {
        int index = NUM_TOTAL_DIG - NEEDELEMENTS(intg) - NEEDELEMENTS(frac);
        // clear no use values
        for (int i = 0; i < index; i++) {
            values[i] = 0;
        }
        if (intg) {
            int firstDigits = intg % DIG_PER_INT32;
            if (firstDigits) {
                values[index++] = GetPowers10(firstDigits - 1);
            } else {
                values[index++] = GetPowers10( DIG_PER_INT32 - 1);
            }
        } else if (frac) {
            values[index++] = GetPowers10( DIG_PER_INT32 - 1);
        }
        for (int i = index; i < NUM_TOTAL_DIG; i++) {
            values[i] = 0;
        }
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::TransferData(const Decimal *v) {
        if (intg >= v->intg && frac >= v->frac) {
            SET_MODE(mode, GET_MODE(v->mode));
            SET_ERR(error, GET_ERR(v->error));
            int shift = NEEDELEMENTS(frac) - NEEDELEMENTS(v->frac);
            for (int i = shift; i < NUM_TOTAL_DIG; i++) {
                values[i - shift] = v->values[i];
            }
        } else {
            assert(0);
            SET_MODE(mode, GET_MODE(v->mode));
            SET_ERR(error, ERR_OVER_FLOW);
        }
        assert(intg + frac <= SUPPORTED_MAX_PRECISION && frac <= SUPPORTED_MAX_SCALE);
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::AlignAddSubData(Decimal &d) {
        if (frac == d.frac) {
            //do nothing
            return;
        }
        int fracc = NEEDELEMENTS(frac);
        int fracd = NEEDELEMENTS(d.frac);
        //align integer and frac part
        if (fracc == fracd) {
            //do nothing
            return;
        }
        if (fracc > fracd) {
            //shift forward d only, and discard high number
            int shift = fracc - fracd;
            for (int i = 0; i < NUM_TOTAL_DIG - shift; i++) {
                d.values[i] = d.values[i + shift];
            }
            for (int i = NUM_TOTAL_DIG - shift; i < NUM_TOTAL_DIG; i++) {
                d.values[i] = 0;
            }
        } else {
            //shift forward current only, and discard high number
            int shift = fracd - fracc;
            for (int i = 0; i < NUM_TOTAL_DIG - shift; i++) {
                values[i] = values[i + shift];
            }
            for (int i = NUM_TOTAL_DIG - shift; i < NUM_TOTAL_DIG; i++) {
                values[i] = 0;
            }
        }
    }

    ARIES_HOST_DEVICE_NO_INLINE void Decimal::initialize(uint32_t ig, uint32_t fc, uint32_t m) {
        if (fc > SUPPORTED_MAX_SCALE) {
            fc = SUPPORTED_MAX_SCALE;
        }
        if (ig + fc > SUPPORTED_MAX_PRECISION) {
            ig = SUPPORTED_MAX_PRECISION - fc;
        }
        intg = ig;
        frac = fc;
        mode = m;
        error = ERR_OK;
//        SET_CALC_INTG(mode, intg);
//        SET_CALC_FRAC(error, frac);
        aries_memset(values, 0x00, sizeof(values));
    }

    ARIES_HOST_DEVICE_NO_INLINE double Decimal::GetDouble() const {
        double z = 0;
        int frac0 = NEEDELEMENTS(frac);
        for (int i = 0; i < NUM_TOTAL_DIG - frac0; i++) {
            if (values[i]) {
                z += values[i];
            }
            if (z) {
                z *= PER_DEC_MAX_SCALE;
            }
        }
        //handle scale part
        double s = 0;
        for (int i = NUM_TOTAL_DIG - frac0; i < NUM_TOTAL_DIG; i++) {
            if (values[i]) {
                s += values[i];
            }
            if (s) {
                s *= PER_DEC_MAX_SCALE;
            }
        }
        for (int i = 0; i < frac0; i++) {
            s /= PER_DEC_MAX_SCALE;
        }
        z += s;
        return z / PER_DEC_MAX_SCALE;
    }

    ARIES_HOST_DEVICE_NO_INLINE int64_t Decimal::ToInt64() const {
        //only 2 digits are valid and no frac part
        int64_t res = values[INDEX_LAST_DIG];
        if (values[INDEX_LAST_DIG - 1]) {
            res += (int64_t) values[INDEX_LAST_DIG - 1] * PER_DEC_MAX_SCALE;
        }
        return res;
    }
    ARIES_HOST_DEVICE_NO_INLINE bool Decimal::CheckIfValidStr2Dec(char * str)
    {
        if (*str == '-') ++str;
        for ( int i = 0; i < aries_strlen(str); ++i )
        {
            if (aries_is_digit(str[i]))
            {
                continue;
            }
            if (str[i] == '.')
            {
                continue;
            }
            return false;
        }
        return true;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool Decimal::CheckIfValidStr2Dec(char * str, int len)
    {
        if (*str == '-') ++str;
        for ( int i = 0; i < aries_strlen(str, len); ++i )
        {
            if (aries_is_digit(str[i]))
            {
                continue;
            }
            if (str[i] == '.')
            {
                continue;
            }
            return false;
        }
        return true;
    }

    ARIES_HOST_DEVICE_NO_INLINE bool Decimal::StringToDecimal( char * str, int len )
    {
        if (!CheckIfValidStr2Dec(str, len))
        {
            return false;
        }
        char sign = 1;
        if (*str == '-') {
            ++str;
            sign = -1;
        }
        char *intgend = aries_strchr(str, '.');
        int strLen = aries_strlen(str, len);
        int intgLen = intgend ? intgend - str : strLen;
        int fracLen = intgend ? strLen - intgLen - 1 : 0;
        assert(fracLen <= SUPPORTED_MAX_SCALE);
        assert(intgLen + fracLen <= SUPPORTED_MAX_PRECISION);
        intg = intgLen;
        frac = fracLen;
        SET_CALC_INTG(mode, intg);
        SET_CALC_FRAC(error, frac);
        int intg0 = NEEDELEMENTS(intgLen);
        int frac0 = NEEDELEMENTS(fracLen);
        int pos = NUM_TOTAL_DIG - frac0 - intg0;
        char temp[16];
        //handle intg part
        int firstLen = intgLen % DIG_PER_INT32;
        if (firstLen) {
            aries_strncpy(temp, str, firstLen);
            temp[firstLen] = 0;
            values[pos++] = aries_atoi(temp);
            str += firstLen;
        }
        for (int i = pos; i < NUM_TOTAL_DIG - frac0; i++) {
            aries_strncpy( temp, str, DIG_PER_INT32);
            temp[DIG_PER_INT32] = 0;
            values[i] = aries_atoi(temp);
            str += DIG_PER_INT32;
        }
        //handle frac part
        if (intgend) {
            str = intgend + 1;
            for (int i = NUM_TOTAL_DIG - frac0; i < NUM_TOTAL_DIG - 1; i++) {
                aries_strncpy( temp, str, DIG_PER_INT32);
                temp[DIG_PER_INT32] = 0;
                values[i] = aries_atoi(temp);
                str += DIG_PER_INT32;
            }
            //handle last one
            aries_strcpy(temp, str);
            values[INDEX_LAST_DIG] = aries_atoi(temp);
            int frac1 = fracLen % DIG_PER_INT32;
            if (frac1) {
                values[INDEX_LAST_DIG] *= GetPowers10( DIG_PER_INT32 - frac1);
            }
        }
        if (sign == -1) {
            #pragma unroll
            for (int i = 0; i < NUM_TOTAL_DIG; ++i) {
                values[i] = -values[i];
            }
        }
        return true;
    }

    /* mysql> select 999999999999999999999999999999999999999999999999999999999999999999999999999999999999;
       +--------------------------------------------------------------------------------------+
       | 999999999999999999999999999999999999999999999999999999999999999999999999999999999999 |
       +--------------------------------------------------------------------------------------+
       |                    99999999999999999999999999999999999999999999999999999999999999999 |
       +--------------------------------------------------------------------------------------+
       1 row in set, 1 warning (0.00 sec)

       mysql> show warnings;
       +---------+------+------------------------------------------------------------------------------------------------------------------------+
       | Level   | Code | Message                                                                                                                |
       +---------+------+------------------------------------------------------------------------------------------------------------------------+
       | Warning | 1292 | Truncated incorrect DECIMAL value: '999999999999999999999999999999999999999999999999999999999999999999999999999999999' |
       +---------+------+------------------------------------------------------------------------------------------------------------------------+
    */
    ARIES_HOST_DEVICE_NO_INLINE bool Decimal::StringToDecimal( char * str )
    {
        if (!CheckIfValidStr2Dec(str))
        {
            return false;
        }
        char sign = 1;
        if (*str == '-') {
            ++str;
            sign = -1;
        }
        char *intgend = aries_strchr(str, '.');
        int strLen = aries_strlen(str);
        int intgLen = intgend ? intgend - str : strLen;
        int fracLen = intgend ? strLen - intgLen - 1 : 0;
        assert(fracLen <= SUPPORTED_MAX_SCALE);
        assert(intgLen + fracLen <= SUPPORTED_MAX_PRECISION);
        intg = intgLen;
        frac = fracLen;
        SET_CALC_INTG(mode, intg);
        SET_CALC_FRAC(error, frac);
        int intg0 = NEEDELEMENTS(intgLen);
        int frac0 = NEEDELEMENTS(fracLen);
        int pos = NUM_TOTAL_DIG - frac0 - intg0;
        char temp[16];
        //handle intg part
        int firstLen = intgLen % DIG_PER_INT32;
        if (firstLen) {
            aries_strncpy(temp, str, firstLen);
            temp[firstLen] = 0;
            values[pos++] = aries_atoi(temp);
            str += firstLen;
        }
        for (int i = pos; i < NUM_TOTAL_DIG - frac0; i++) {
            aries_strncpy( temp, str, DIG_PER_INT32);
            temp[DIG_PER_INT32] = 0;
            values[i] = aries_atoi(temp);
            str += DIG_PER_INT32;
        }
        //handle frac part
        if (intgend) {
            str = intgend + 1;
            for (int i = NUM_TOTAL_DIG - frac0; i < NUM_TOTAL_DIG - 1; i++) {
                aries_strncpy( temp, str, DIG_PER_INT32);
                temp[DIG_PER_INT32] = 0;
                values[i] = aries_atoi(temp);
                str += DIG_PER_INT32;
            }
            //handle last one
            aries_strcpy(temp, str);
            values[INDEX_LAST_DIG] = aries_atoi(temp);
            int frac1 = fracLen % DIG_PER_INT32;
            if (frac1) {
                values[INDEX_LAST_DIG] *= GetPowers10( DIG_PER_INT32 - frac1);
            }
        }
        if (sign == -1) {
            #pragma unroll
            for (int i = 0; i < NUM_TOTAL_DIG; ++i) {
                values[i] = -values[i];
            }
        }
        return true;
    }

    //below methods are for computing long 10 based integer by char string
#ifdef COMPUTE_BY_STRING
    ARIES_HOST_DEVICE_NO_INLINE char* Decimal::GetDivDecimalStr( char *to)
    {
        int start = -1;
        for( int i = 0; i < NUM_TOTAL_DIG; i++ )
        {
            if (values[i] == 0)
            continue;
            start = i;
            break;
        }
        if( start == -1 )
        {
            aries_strcpy( to, "0");
        }
        else
        {
            aries_sprintf( to, "%d", values[start++] );
            char temp[16];
            for( int i = start; i < NUM_TOTAL_DIG - 1; i++ )
            {
                aries_sprintf( temp, values[i] < 0 ? "%010d" : "%09d", values[i] );
                aries_strcat( to, values[i] < 0 ? temp + 1 : temp );
            }
            //handle last one
            int remainLen = frac % DIG_PER_INT32;
            int end = NUM_TOTAL_DIG - 1;
            aries_sprintf( temp, values[end] < 0 ? "%010d" : "%09d", values[end] );
            aries_strncat( to, values[end] < 0 ? temp + 1 : temp, remainLen );
        }
        return to;
    }

    ARIES_HOST_DEVICE_NO_INLINE int Decimal::Compare( char *cmp1, char *cmp2)
    {
        size_t len1 = aries_strlen(cmp1), len2 = aries_strlen(cmp2);
        if (len1 > len2)
        {
            return 1;
        }
        else if (len1 < len2)
        {
            return -1;
        }
        else
        {
            return aries_strcmp(cmp1, cmp2);
        }
    }

    ARIES_HOST_DEVICE_NO_INLINE int Decimal::FindFirstNotOf( char *s, char ch)
    {
        char *p = s;
        if (ch)
        {
            while (*p && *p == ch) ++p;
        }
        return p - s;
    }

    ARIES_HOST_DEVICE_NO_INLINE char* Decimal::Erase( char *s, int startPos, int n)
    {
        int l = aries_strlen(s);
        if (l <= startPos || n <= 0)
        {
            return s;
        }
        int endPos = startPos + n;
        if (l <= endPos)
        {
            s[startPos] = 0;
        }
        else
        {
            aries_strcpy(s + startPos, s + endPos);
        }
        return s;
    }

    ARIES_HOST_DEVICE_NO_INLINE char* Decimal::DivInt(char *str1, char *str2, int mode, char * result)
    {
        char quotient[128] =
        {   0}, residue[128] =
        {   0};   //定义商和余数
        int signds = 1, signdt = 1;
        if (*str2 == '0')//判断除数是否为0
        {
            error = ERR_DIV_BY_ZERO;
            aries_strcpy(result, "ERROR!");
            return result;
        }
        if (*str1 == '0')     //判断被除数是否为0
        {
            aries_strcpy(quotient, "0");
            aries_strcpy(residue, "0");
        }
        if (str1[0] == '-')
        {
            ++str1;
            signds *= -1;
            signdt = -1;
        }
        if (str2[0] == '-')
        {
            ++str2;
            signds *= -1;
        }
        int res = Compare(str1, str2);
        if (res < 0)
        {
            aries_strcpy(quotient, "0");
            aries_strcpy(residue, str1);
        }
        else if (res == 0)
        {
            aries_strcpy(quotient, "1");
            aries_strcpy(residue, "0");
        }
        else
        {
            int divitendLen = aries_strlen(str1), divisorLen = aries_strlen(str2);
            char tempstr[128] =
            {   0};
            aries_strncpy(tempstr, str1, divisorLen - 1);
            tempstr[divisorLen] = 0;
            int len = 0;
            //模拟手工除法竖式
            for (int i = divisorLen - 1; i < divitendLen; i++)
            {
                len = aries_strlen(tempstr);
                tempstr[len] = str1[i];
                tempstr[len + 1] = 0;
                Erase(tempstr, 0, FindFirstNotOf(tempstr, '0'));
                if (aries_strlen(tempstr) == 0)
                {
                    aries_strcpy(tempstr, "0");
                }
                for (char ch = '9'; ch >= '0'; ch--) //试商
                {
                    char temp[16];
                    temp[0] = ch;
                    temp[1] = 0;
                    char r[128] =
                    {   0};
                    if( Compare( MulInt( (char *)str2, (char *)temp, r), tempstr ) <= 0 )
                    {
                        len = aries_strlen(quotient);
                        quotient[len] = ch;
                        quotient[len + 1] = 0;
                        SubInt( tempstr, MulInt( str2, temp, r ) , tempstr);
                        break;
                    }
                }
            }
            aries_strcpy(residue, tempstr);
        }
        //去除结果中的前导0
        Erase(quotient, 0, FindFirstNotOf(quotient, '0'));
        if (aries_strlen(quotient) == 0)
        {
            aries_strcpy(quotient, "0");
        }
        if ((signds == -1) && (quotient[0] != '0'))
        {
            InsertCh(quotient, 0, '-');
        }
        if ((signdt == -1) && (residue[0] != '0'))
        {
            InsertCh(residue, 0, '-');
        }
        if (mode == 1)
        {
            aries_strcpy(result, quotient);
        }
        else
        {
            aries_strcpy(result, residue);
        }
        return result;
    }

    ARIES_HOST_DEVICE_NO_INLINE char* Decimal::MulInt(char *str1, char *str2, char * result)
    {
        int sign = 1;
        char str[128] =
        {   0};  //记录当前值
        str[0] = '0';
        if (str1[0] == '-')
        {
            sign *= -1;
            str1++;
        }
        if (str2[0] == '-')
        {
            sign *= -1;
            str2++;
        }
        int i, j;
        size_t L1 = aries_strlen(str1), L2 = aries_strlen(str2);
        for (i = L2 - 1; i >= 0; i--)              //模拟手工乘法竖式
        {
            char tempstr[128] =
            {   0};
            int int1 = 0, int2 = 0, int3 = int(str2[i]) - '0';
            if (int3 != 0)
            {
                for (j = 1; j <= (int)(L2 - 1 - i); j++)
                {
                    tempstr[j - 1] = 0;
                }
                for (j = L1 - 1; j >= 0; j--)
                {
                    int1 = (int3*(int(str1[j]) - '0') + int2) % 10;
                    int2 = (int3*(int(str1[j]) - '0') + int2) / 10;
                    InsertCh(tempstr, 0, char(int1 + '0'));
                }
                if (int2 != 0)
                {
                    InsertCh(tempstr, 0, char(int2 + '0'));
                }
            }
            AddInt(str, tempstr, str);
        }
        //去除结果中的前导0
        Erase(str, 0, FindFirstNotOf(str, '0'));
        if (aries_strlen(str) == 0)
        {
            aries_strcpy(str, "0");
        }
        if ((sign == -1) && (str[0] != '0'))
        {
            InsertCh(str, 0, '-');
        }

        aries_strcpy(result, str);
        return result;
    }

    ARIES_HOST_DEVICE_NO_INLINE char* Decimal::SubInt(char *str1, char *str2, char *result)
    {
        int sign = 1; //sign为符号位
        int i, j;
        if (str2[0] == '-')
        {
            result = AddInt(str1, str2 + 1, result);
        }
        else
        {
            int res = Compare(str1, str2);
            if (res == 0)
            {
                aries_strcpy(result, "0");
                return result;
            }
            if (res < 0)
            {
                sign = -1;
                char *temp = str1;
                str1 = str2;
                str2 = temp;
            }
            int len1 = aries_strlen(str1), len2 = aries_strlen(str2);
            int tmplen = len1 - len2;
            for (i = len2 - 1; i >= 0; i--)
            {
                if (str1[i + tmplen] < str2[i])          //借位
                {
                    j = 1;
                    while (1)
                    {
                        if (str1[tmplen - j + i] == '0')
                        {
                            str1[i + tmplen - j] = '9';
                            j++;
                        }
                        else
                        {
                            str1[i + tmplen - j] = char(int(str1[i + tmplen - j]) - 1);
                            break;
                        }
                    }
                    result[i + tmplen] = char(str1[i + tmplen] - str2[i] + ':');
                }
                else
                {
                    result[i + tmplen] = char(str1[i + tmplen] - str2[i] + '0');
                }
            }
            for (i = tmplen - 1; i >= 0; i--)
            result[i] = str1[i];
        }
        //去出结果中多余的前导0
        Erase(result, 0, FindFirstNotOf(result, '0'));
        if (aries_strlen(result) == 0)
        {
            aries_strcpy(result, "0");
        }
        if ((sign == -1) && (result[0] != '0'))
        {
            InsertCh(result, 0, '-');
        }
        return result;
    }

    ARIES_HOST_DEVICE_NO_INLINE char* Decimal::AddInt(char *str1, char *str2, char *result)
    {
        int sign = 1;          //sign为符号为
        char str[128] =
        {   0};
        if (str1[0] == '-')
        {
            if (str2[0] == '-')       //负负
            {
                sign = -1;
                AddInt(str1 + 1, str2 + 1, str);       //去掉正负号
            }
            else             //负正
            {
                SubInt(str2, str1 + 1, str);
            }
        }
        else
        {
            if (str2[0] == '-')        //正负
            {
                SubInt(str1, str2 + 1, str);
            }
            else                    //正正，把两个整数对齐，短整数前面加0补齐
            {
                int L1 = aries_strlen(str1), L2 = aries_strlen(str2);
                int i, l;
                char tmp[128];
                if (L1 < L2)
                {
                    l = L2 - L1;
                    for (i = 0; i < l; i++)
                    {
                        tmp[i] = '0';
                    }
                    tmp[l] = 0;
                    InsertStr(str1, 0, tmp);
                }
                else
                {
                    l = L1 - L2;
                    for (i = 0; i < L1 - L2; i++)
                    {
                        tmp[i] = '0';
                    }
                    tmp[l] = 0;
                    InsertStr(str2, 0, tmp);
                }
                int int1 = 0, int2 = 0; //int2记录进位
                l = aries_strlen(str1);
                for (i = l - 1; i >= 0; i--)
                {
                    int1 = (int(str1[i]) - '0' + int(str2[i]) - '0' + int2) % 10;
                    int2 = (int(str1[i]) - '0' + int(str2[i]) - '0' + int2) / 10;
                    str[i + 1] = char(int1 + '0');
                }
                str[l + 1] = 0;
                if (int2 != 0)
                {
                    result[0] = char(int2 + '0');
                }
                else
                {
                    aries_strcpy(str, str + 1);
                }
            }
        }
        //运算符处理符号
        if ((sign == -1) && (str[0] != '0'))
        {
            InsertCh(str, 0, '-');
        }
        aries_strcpy(result, str);
        return result;
    }

    ARIES_HOST_DEVICE_NO_INLINE char* Decimal::InsertStr(char *str, int pos, char *in)
    {
        int len = aries_strlen(str);
        int inLen = aries_strlen(in);
        assert(len + inLen < 128);
        int insertPos = len < pos ? len : pos;
        if (len == insertPos)
        {
            aries_strcat(str, in);
        }
        else
        {
            char tmp[128];
            aries_strcpy(tmp, str + insertPos);
            aries_strcpy(str + insertPos, in);
            aries_strcpy(str + insertPos + inLen, tmp);
        }
        return str;
    }

    ARIES_HOST_DEVICE_NO_INLINE char* Decimal::InsertCh(char *str, int pos, char in)
    {
        char temp[8];
        temp[0] = in;
        temp[1] = 0;
        return InsertStr(str, pos, temp);
    }
#endif

END_ARIES_ACC_NAMESPACE

