--  This Source Code Form is subject to the terms of the Mozilla Public
--  License, v. 2.0. If a copy of the MPL was not distributed with this
--  file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

-- This is used to define the 'keepRedundantContraint' helper here where it is
-- safe to define, and use it in other Json modules where we do not want to turn
-- -fno-warn-redundant-constraints for the entire module, but still want some
-- redundant constraints in order to enforce some restriction at the type-level
-- to not shoot ourselves in the foot by accident.
{-# OPTIONS_GHC -fno-warn-redundant-constraints #-}
{-# OPTIONS_GHC -fno-warn-unticked-promoted-constructors #-}

module Ogmios.Prelude
    ( -- * relude, minus STM
      module Relude

      -- * generic-lens commons
    , HasType
    , view
    , typed
    , (^?)
    , (^.)

      -- * StrictMaybe
    , StrictMaybe
    , maybeToStrictMaybe

      -- * Array
    , Array
    , mapToArray

      -- * Set
    , traverset

      -- * Ledger & consensus common
    , Era
    , EraCrypto
    , Crypto
    , StandardCrypto
    , CardanoEras
    , AllegraEra
    , AlonzoEra
    , BabbageEra
    , ConwayEra
    , MaryEra
    , ShelleyEra

      -- * CBOR Decoding
    , decodeCbor
    , decodeCborWith
    , decodeCborAnn
    , decodeCborAnnWith

      -- * type-level helpers
    , keepRedundantConstraint
    , LastElem
    , Elem
    , Or
    , HKD
    , (:\:)
    , EraProto
    , SomeShelleyEra (..)
    , ByronEra
    , EraIndex (..)
    , ShelleyBasedEra (..)
    , IsShelleyBasedEra (..)
    , BlockCrypto
    , fromEraIndex
    ) where

import Cardano.Ledger.Core
    ( ByronEra
    )
import Cardano.Ledger.Crypto
    ( Crypto
    , StandardCrypto
    )
import Cardano.Ledger.Era
    ( Era
    , EraCrypto
    )
import Data.Aeson
    ( ToJSON (..)
    )
import Data.Array
    ( Array
    , array
    )
import Data.Generics.Internal.VL.Lens
    ( view
    , (^.)
    )
import Data.Generics.Product.Typed
    ( HasType
    , typed
    )
import Data.Maybe.Strict
    ( StrictMaybe
    , maybeToStrictMaybe
    )
import Data.Profunctor.Unsafe
    ( (#.)
    )
import Data.SOP.Strict
    ( NS (..)
    )
import Formatting.Buildable
    ( build
    )
import GHC.Ix
    ( Ix
    )
import GHC.TypeLits
    ( ErrorMessage (..)
    , TypeError
    )
import Ouroboros.Consensus.Cardano
    ( CardanoBlock
    )
import Ouroboros.Consensus.Cardano.Block
    ( CardanoEras
    )
import Ouroboros.Consensus.HardFork.Combinator
    ( EraIndex (..)
    )
import Ouroboros.Consensus.Protocol.Praos
    ( Praos
    )
import Ouroboros.Consensus.Protocol.TPraos
    ( TPraos
    )
import Ouroboros.Consensus.Shelley.Eras
    ( AllegraEra
    , AlonzoEra
    , BabbageEra
    , ConwayEra
    , MaryEra
    , ShelleyEra
    )
import Relude hiding
    ( MVar
    , Nat
    , STM
    , TMVar
    , TVar
    , atomically
    , catchSTM
    , isEmptyTMVar
    , mkWeakTMVar
    , modifyTVar'
    , newEmptyMVar
    , newEmptyTMVar
    , newEmptyTMVarIO
    , newMVar
    , newTMVar
    , newTMVarIO
    , newTVar
    , newTVarIO
    , putMVar
    , putTMVar
    , readMVar
    , readTMVar
    , readTVar
    , readTVarIO
    , swapMVar
    , swapTMVar
    , takeMVar
    , takeTMVar
    , throwSTM
    , traceM
    , tryPutMVar
    , tryPutTMVar
    , tryReadMVar
    , tryReadTMVar
    , tryTakeMVar
    , tryTakeTMVar
    , writeTVar
    )

import qualified Cardano.Ledger.Binary.Decoding as Binary
import qualified Cardano.Ledger.Core as Ledger
import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Data.Text.Lazy.Builder as TL

mapToArray :: Ix k => Map k v -> Array k v
mapToArray m =
  array
    (fst (Map.findMin m), fst (Map.findMax m))
    (Map.toList m)

traverset :: (Ord b, Applicative f) => (a -> f b) -> Set a -> f (Set b)
traverset f =
    Set.foldr insert (pure Set.empty)
  where
    insert x = liftA2 Set.insert (f x)

-- | Copied from: https://hackage.haskell.org/package/generic-lens-1.1.0.0/docs/src/Data.Generics.Internal.VL.Prism.html
infixl 8 ^?
(^?) :: s -> ((a -> Const (First a) a) -> s -> Const (First a) s) -> Maybe a
s ^? l = getFirst (fmof l (First #. Just) s)
  where fmof l' f = getConst #. l' (Const #. f)

keepRedundantConstraint :: c => Proxy c -> ()
keepRedundantConstraint _ = ()

-- | Access the last element of a type-level list.
type family LastElem xs where
    LastElem '[]       = TypeError ('Text "LastElem: empty list.")
    LastElem (x : '[]) = x
    LastElem (x : xs)  = LastElem xs

type family Elem e es where
    Elem e '[]      = TypeError ('Text "Elem: not found.")
    Elem e (x : es) = Or (e ~ x) (Elem e es)

type family Or (a :: Constraint) (b :: Constraint) :: Constraint where
    Or () b = ()
    Or (x ~ x) b = Or () b
    Or a () = ()
    Or a (x ~ x) = Or a ()

type family HKD f a where
  HKD Identity a = a
  HKD f a = f a

infixr 5 :\:
type family (:\:) (any :: k) (excluded :: k) :: Constraint where
    excluded :\: excluded =
        TypeError ( 'Text "Usage of this function forbids the type '" :<>: 'ShowType excluded :<>: 'Text "'." )
    _ :\: _ = ()

type family EraProto era :: Type where
    EraProto (ShelleyEra crypto) = TPraos crypto
    EraProto (AllegraEra crypto) = TPraos crypto
    EraProto (MaryEra crypto)    = TPraos crypto
    EraProto (AlonzoEra crypto)  = TPraos crypto
    EraProto (BabbageEra crypto) = Praos crypto
    EraProto (ConwayEra crypto)  = Praos crypto

data ShelleyBasedEra era where
    ShelleyBasedEraShelley :: forall crypto. ShelleyBasedEra (ShelleyEra crypto)
    ShelleyBasedEraAllegra :: forall crypto. ShelleyBasedEra (AllegraEra crypto)
    ShelleyBasedEraMary    :: forall crypto. ShelleyBasedEra (MaryEra crypto)
    ShelleyBasedEraAlonzo  :: forall crypto. ShelleyBasedEra (AlonzoEra crypto)
    ShelleyBasedEraBabbage :: forall crypto. ShelleyBasedEra (BabbageEra crypto)
    ShelleyBasedEraConway  :: forall crypto. ShelleyBasedEra (ConwayEra crypto)

deriving instance Show (ShelleyBasedEra era)

data SomeShelleyEra =
    forall era. SomeShelleyEra (ShelleyBasedEra era)

deriving instance Show SomeShelleyEra

instance ToJSON SomeShelleyEra where
    toJSON = \case
        SomeShelleyEra ShelleyBasedEraShelley -> toJSON @Text "shelley"
        SomeShelleyEra ShelleyBasedEraAllegra -> toJSON @Text "allegra"
        SomeShelleyEra ShelleyBasedEraMary    -> toJSON @Text "mary"
        SomeShelleyEra ShelleyBasedEraAlonzo  -> toJSON @Text "alonzo"
        SomeShelleyEra ShelleyBasedEraBabbage -> toJSON @Text "babbage"
        SomeShelleyEra ShelleyBasedEraConway  -> toJSON @Text "conway"

class IsShelleyBasedEra era where
    shelleyBasedEra :: ShelleyBasedEra era

instance IsShelleyBasedEra (ShelleyEra crypto) where
    shelleyBasedEra = ShelleyBasedEraShelley

instance IsShelleyBasedEra (AllegraEra crypto) where
    shelleyBasedEra = ShelleyBasedEraAllegra

instance IsShelleyBasedEra (MaryEra crypto) where
    shelleyBasedEra = ShelleyBasedEraMary

instance IsShelleyBasedEra (AlonzoEra crypto) where
    shelleyBasedEra = ShelleyBasedEraAlonzo

instance IsShelleyBasedEra (BabbageEra crypto) where
    shelleyBasedEra = ShelleyBasedEraBabbage

instance IsShelleyBasedEra (ConwayEra crypto) where
    shelleyBasedEra = ShelleyBasedEraConway

type family BlockCrypto block :: Type where
    BlockCrypto (CardanoBlock crypto) = crypto

-- | Convert an 'EraIndex' to a Shelley-based era.
fromEraIndex
    :: forall crypto. ()
    => EraIndex (CardanoEras crypto)
    -> Maybe SomeShelleyEra
fromEraIndex = \case
    EraIndex                   Z{}       -> Nothing
    EraIndex                (S Z{})      -> Just (SomeShelleyEra ShelleyBasedEraShelley)
    EraIndex             (S (S Z{}))     -> Just (SomeShelleyEra ShelleyBasedEraAllegra)
    EraIndex          (S (S (S Z{})))    -> Just (SomeShelleyEra ShelleyBasedEraMary)
    EraIndex       (S (S (S (S Z{}))))   -> Just (SomeShelleyEra ShelleyBasedEraAlonzo)
    EraIndex    (S (S (S (S (S Z{})))))  -> Just (SomeShelleyEra ShelleyBasedEraBabbage)
    EraIndex (S (S (S (S (S (S Z{})))))) -> Just (SomeShelleyEra ShelleyBasedEraConway)

-- Run a CBOR decoder for a data in a particular era.
decodeCborWith
    :: forall era m a. (Era era, Applicative m)
    => Text
    -> (Binary.DecoderError -> m a)
    -> (forall s. Binary.Decoder s a)
    -> LByteString
    -> m a
decodeCborWith lbl reject decoder bytes =
    either reject pure (Binary.decodeFullDecoder version lbl decoder bytes)
  where
    version = Ledger.eraProtVerLow @era

decodeCbor
    :: forall era m a. (Era era, MonadFail m)
    => Text
    -> (forall s. Binary.Decoder s a)
    -> LByteString
    -> m a
decodeCbor lbl =
    decodeCborWith @era lbl (fail . renderCborDecoderError)

-- Run a CBOR decoder for an annotated data in a particular era.
decodeCborAnnWith
    :: forall era m a. (Era era, Applicative m)
    => Text
    -> (Binary.DecoderError -> m a)
    -> (forall s. Binary.Decoder s (Binary.Annotator a))
    -> LByteString
    -> m a
decodeCborAnnWith lbl reject decoder bytes =
    either reject pure (Binary.decodeFullAnnotator (Ledger.eraProtVerLow @era) lbl decoder bytes)

decodeCborAnn
    :: forall era m a. (Era era, MonadFail m)
    => Text
    -> (forall s. Binary.Decoder s (Binary.Annotator a))
    -> LByteString
    -> m a
decodeCborAnn lbl  =
    decodeCborAnnWith @era lbl (fail . renderCborDecoderError)

-- | Render a CBOR error as a String.
renderCborDecoderError :: Binary.DecoderError -> String
renderCborDecoderError =
    toString . TL.toLazyText . build
