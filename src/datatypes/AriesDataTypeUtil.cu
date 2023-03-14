//
// Created by david.shen on 2019/12/18.
//

#include <cassert>
#include <cstdio>

#include "AriesDataTypeUtil.hxx"

BEGIN_ARIES_ACC_NAMESPACE
    ARIES_HOST_DEVICE_NO_INLINE int aries_is_space(int ch) {
        return (unsigned long) (ch - 9) < 5u || ' ' == ch;
    }

    ARIES_HOST_DEVICE_NO_INLINE int aries_atoi( const char *str, const char *end )
    {
        int sign;
        int n = 0;
        const char *p = str;

        while( p != end && aries_is_space( *p ) )
            p++;
        if( p != end )
        {
            sign = ( '-' == *p ) ? -1 : 1;
            if( '+' == *p || '-' == *p )
                p++;

            for( n = 0; p != end && aries_is_digit( *p ); p++ )
                n = 10 * n + ( *p - '0' );

            if( sign == -1 )
                n = -n;
        }
        return n;
    }

    ARIES_HOST_DEVICE_NO_INLINE int aries_atoi( const char *str )
    {
        int sign;
        int n = 0;
        const char *p = str;

        while( aries_is_space( *p ) )
            p++;

        sign = ( '-' == *p ) ? -1 : 1;
        if( '+' == *p || '-' == *p )
            p++;

        for( n = 0; aries_is_digit( *p ); p++ )
            n = 10 * n + ( *p - '0' );

        if( sign == -1 )
            n = -n;
        return n;
    }

    ARIES_HOST_DEVICE_NO_INLINE int64_t aries_atol( const char *str, const char *end )
    {
        int sign;
        int64_t n = 0;
        const char *p = str;

        while( p != end && aries_is_space( *p ) )
            p++;
        if( p != end )
        {
            sign = ( '-' == *p ) ? -1 : 1;
            if( '+' == *p || '-' == *p )
                p++;

            for( n = 0; p != end && aries_is_digit( *p ); p++ )
                n = 10 * n + ( *p - '0' );

            if( sign == -1 )
                n = -n;
        }
        return n;
    }

    ARIES_HOST_DEVICE_NO_INLINE int64_t aries_atol( const char *str )
    {
        int sign;
        int64_t n = 0;
        const char *p = str;

        while( aries_is_space( *p ) )
            p++;

        sign = ( '-' == *p ) ? -1 : 1;
        if( '+' == *p || '-' == *p )
            p++;

        for( n = 0; aries_is_digit( *p ); p++ )
            n = 10 * n + ( *p - '0' );

        if( sign == -1 )
            n = -n;
        return n;
    }

    ARIES_HOST_DEVICE_NO_INLINE int aries_strlen(const char *str) {
        const char *p = str;
        while (*p++);

        return (int) (p - str - 1);
    }

    ARIES_HOST_DEVICE_NO_INLINE int aries_strlen(const char *str, int len) {
        return *( str + len - 1 ) ? len : aries_strlen( str );
    }

    ARIES_HOST_DEVICE_NO_INLINE char *aries_strcpy(char *strDest, const char *strSrc) {
        if (strDest == strSrc) {
            return strDest;
        }
        assert((strDest != NULL) && (strSrc != NULL));
        char *address = strDest;
        while ((*strDest++ = *strSrc++));
        return address;
    }

    ARIES_HOST_DEVICE_NO_INLINE char *aries_strncpy(char *strDest, const char *strSrc, unsigned int count) {
        if (strDest == strSrc) {
            return strDest;
        }
        assert((strDest != NULL) && (strSrc != NULL));
        char *address = strDest;
        while (count-- && *strSrc)
            *strDest++ = *strSrc++;
        *strDest = 0;
        return address;
    }

    ARIES_HOST_DEVICE_NO_INLINE char *aries_strcat(char *strDes, const char *strSrc) {
        assert((strDes != NULL) && (strSrc != NULL));
        char *address = strDes;
        while (*strDes)
            ++strDes;
        while ((*strDes++ = *strSrc++));
        return address;
    }

    ARIES_HOST_DEVICE_NO_INLINE char *aries_strncat(char *strDes, const char *strSrc, unsigned int count) {
        assert((strDes != NULL) && (strSrc != NULL));
        char *address = strDes;
        while (*strDes)
            ++strDes;
        while (count-- && *strSrc)
            *strDes++ = *strSrc++;
        *strDes = 0;
        return address;
    }

    ARIES_HOST_DEVICE_NO_INLINE char *aries_strchr(const char *str, int ch) {
        while (*str && *str != (char) ch)
            str++;

        if (*str == (char) ch)
            return ((char *) str);

        return 0;
    }

    ARIES_HOST_DEVICE_NO_INLINE char *aries_sprintf(char *dst, const char *fmt, int v) {
        int startPos = 0;
        int len = aries_strlen(fmt);
        //only support format : %d, %010d
        if (fmt[startPos++] != '%' || fmt[len - 1] != 'd') {
            assert(0);
            return dst;
        }

        int outLen = -1;
        bool fillwithz = false;
        if (fmt[startPos] == '0') {
            fillwithz = true;
            ++startPos;
        }
        char tmp[128];
        if (startPos + 1 < len) {
            aries_strncpy(tmp, fmt + startPos, len - startPos - 1);
            outLen = aries_atoi(tmp);
        }
        //no out
        if (outLen == 0) {
            dst[0] = '0';
            dst[1] = 0;
            return dst;
        }
        int negsign = 0;
        int val = v;
        startPos = 0;
        if (val < 0) {
            negsign = 1;
            val = -val;
        }
        do {
            tmp[startPos++] = char('0' + val % 10);
            val /= 10;
        } while (val > 0);

        len = startPos;
        startPos = 0;
        if (negsign) {
            dst[startPos++] = '-';
        }
        if (outLen == -1) {
            if (len == 0) {
                dst[startPos++] = '0';
            } else {
                for (int i = len - 1; i >= 0; i--) {
                    dst[startPos++] = tmp[i];
                }
            }
            dst[startPos] = 0;
        } else {
            int realLen = len + negsign;
            if (fillwithz) {
                int rep0 = outLen - realLen;
                if (rep0 > 0) {
                    for (int i = 0; i < rep0; i++) {
                        dst[startPos++] = '0';
                    }
                }
            }
            int cpylen = outLen - startPos;
            cpylen = cpylen > len ? len : cpylen;
            for (int i = cpylen - 1; i >= 0; i--) {
                dst[startPos++] = tmp[i];
            }
            dst[startPos] = 0;
        }
        return dst;
    }

    ARIES_HOST_DEVICE_NO_INLINE void *aries_memset(void *dst, int val, unsigned long ulcount) {
        if (!dst)
            return 0;
        char *pchdst = (char *) dst;
        while (ulcount--)
            *pchdst++ = (char) val;

        return dst;
    }

    ARIES_HOST_DEVICE_NO_INLINE void *aries_memcpy(void *dst, const void *src, unsigned long ulcount) {
        if (!(dst && src))
            return 0;
        if (!ulcount)
            return dst;
        char *pchdst = (char *) dst;
        char *pchsrc = (char *) src;
        while (ulcount--)
            *pchdst++ = *pchsrc++;

        return dst;
    }

    ARIES_HOST_DEVICE_NO_INLINE int aries_strcmp(const char *source, const char *dest) {
        int ret = 0;
        if (!source || !dest)
            return -2;
        while (!(ret = *(unsigned char *) source - *(unsigned char *) dest) && *dest) {
            source++;
            dest++;
        }

        if (ret < 0)
            ret = -1;
        else if (ret > 0)
            ret = 1;

        return (ret);
    }

    ARIES_HOST_DEVICE_NO_INLINE char *aries_strstr(const char *strSrc, const char *str) {
        assert(strSrc != NULL && str != NULL);
        const char *s = strSrc;
        const char *t = str;
        for (; *strSrc; ++strSrc) {
            for (s = strSrc, t = str; *t && *s == *t; ++s, ++t);
            if (!*t)
                return (char *) strSrc;
        }
        return 0;
    }

    /*
      Converts integer to its string representation in decimal notation.

    SYNOPSIS
    aries_int10_to_str()
            val     - value to convert
            dst     - points to buffer where string representation should be stored
            radix   - flag that shows whenever val should be taken as signed or not

    DESCRIPTION
            This is version of int2str() (in file int2str.cc ) function which is optimized for normal case
    of radix 10/-10. It takes only sign of radix parameter into account and
    not its absolute value.

    RETURN VALUE
    Pointer to ending NUL character.
    */

    ARIES_HOST_DEVICE_NO_INLINE char *aries_int10_to_str(long int val,char *dst,int radix)
    {
        char buffer[64];
        char *p;
        long int new_val;
        auto uval = (unsigned long int) val;

        if (radix < 0)				/* -10 */
        {
            if (val < 0)
            {
                *dst++ = '-';
                /* Avoid integer overflow in (-val) for LONGLONG_MIN (BUG#31799). */
                uval = (unsigned long int)0 - uval;
            }
        }

        p = &buffer[sizeof(buffer)-1];
        *p = '\0';
        new_val= (long) (uval / 10);
        *--p = '0'+ (char) (uval - (unsigned long) new_val * 10);
        val = new_val;

        while (val != 0)
        {
            new_val=val/10;
            *--p = '0' + (char) (val-new_val*10);
            val= new_val;
        }
        while ((*dst++ = *p++) != 0) ;
        return dst-1;
    }

END_ARIES_ACC_NAMESPACE
