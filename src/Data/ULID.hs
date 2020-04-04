{- |
This library implements the
Universally Unique Lexicographically Sortable Identifier,
as described at https://github.com/alizain/ulid.

UUID can be suboptimal for many uses-cases because:

* It isn't the most character efficient way of encoding 128 bits of randomness
* UUID v1/v2 is impractical in many environments,
    as it requires access to a unique, stable MAC address
* UUID v3/v5 requires a unique seed and produces randomly distributed IDs,
    which can cause fragmentation in many data structures
* UUID v4 provides no other information than randomness,
    which can cause fragmentation in many data structures

Instead, herein is proposed ULID:

* 128-bit compatibility with UUID
* 1.21e+24 unique ULIDs per millisecond
* Lexicographically sortable!
* Canonically encoded as a 26 character text,
    as opposed to the 36 character UUID
* Uses Douglas Crockford's base32 for better efficiency and readability
    (5 bits per character)
* Case insensitive
* No special characters (URL safe)
-}

{-# LANGUAGE DeriveDataTypeable #-}
module Data.ULID (
    ULID(..),
    getULIDTime,
    getULID,
    ulidToInteger,
    ulidFromInteger
) where

import           Control.DeepSeq
import           Data.Binary
import qualified Data.ByteString.Lazy  as LBS
import           Data.Data
import           Data.Hashable
import           Data.Monoid           ((<>))
import           Data.Text as T
import           Data.Time.Clock.POSIX
import           System.IO.Unsafe
import qualified System.Random         as R

import           Data.Binary.Roll
import           Data.ULID.Random
import           Data.ULID.TimeStamp


{- |
> t <- getULIDTimeStamp
> r <- getULIDRandom
> pure $ ULID t r
-}
data ULID = ULID
  { timeStamp :: !ULIDTimeStamp
  , random    :: !ULIDRandom
  }
  deriving (Eq, Typeable, Data)

instance Ord ULID where
    compare (ULID ts1 _) (ULID ts2 _) = compare ts1 ts2

instance Show ULID where
    show (ULID ts bytes) = (show ts) ++ (show bytes)

instance Read ULID where
    readsPrec _ str = do
        (ts, str2) <- reads str
        (rn, str3) <- reads str2
        return (ULID ts rn, str3)

instance Binary ULID where
    put (ULID ts bytes) = put ts <> put bytes
    get = do
        ts <- get
        bytes <- get
        return $ ULID ts bytes

-- | Because of the strictness annotations,
-- this shouldn't be needed and shouldn't do anything.
-- This is tested and confirmed in the benchmark,
-- but since the work to put it here has already been done
-- it's no harm to leave it in.
instance NFData ULID where
    rnf (ULID ts bytes) = rnf ts `seq` (rnf bytes `seq` ())

instance R.Random ULID where
    randomR _ = R.random -- ignore range
    random g = unsafePerformIO $ do
        t <- getULIDTimeStamp
        let (r, g') = mkULIDRandom g
        return (ULID t r, g')
    randomIO = getULID

instance Hashable ULID where
    hashWithSalt salt ulid = hashWithSalt salt (encode ulid)


-- | Derive a ULID using a specified time and default random number generator
getULIDTime
  :: POSIXTime  -- ^ Specified UNIX time with millisecond precision
                --   (e.g. 1469918176.385)
  -> IO ULID
getULIDTime t = do
    let t' = mkULIDTimeStamp t
    r <- getULIDRandom
    return $ ULID t' r


-- | Derive a ULID using the current time and default random number generator
getULID :: IO ULID
getULID = do
    t <- getULIDTimeStamp
    r <- getULIDRandom
    return $ ULID t r


-- | Convert a ULID to its corresponding (at most) 128-bit Integer.
-- Integer equivalents retain sortable trait (same sort order).
-- This could be useful for storing in a database using a smaller field
-- than storing the shown `Text`,
-- but still human-readable unlike the Binary version.
ulidToInteger :: ULID -> Integer
ulidToInteger = roll.(LBS.unpack).encode


-- | Convert a ULID from its corresponding 128-bit Integer.
ulidFromInteger
  :: Integer -- ^ The ULID's Integer equivalent, as generated by toInteger
  -> Either Text ULID
ulidFromInteger n
    | n < 0 = Left "Value must not be negative"
    | n > maxValidInteger = Left
        "Value must not be larger than the maximum safe Integer size (128 bits)"
    | otherwise = Right
        . decode . LBS.pack . (unroll 16) $ n  -- 16 bytes = 128 bit
  where
    maxValidInteger :: Integer
    maxValidInteger = (2 ^ 128) - 1
