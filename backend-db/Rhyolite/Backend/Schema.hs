{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -fno-warn-orphans #-}

module Rhyolite.Backend.Schema where

import Data.Aeson (FromJSON, ToJSON, decode', eitherDecode', encode)
import Data.Functor.Identity (Identity(..))
import Data.Typeable (Proxy(..), Typeable)
import Database.Groundhog.Core
import Database.Groundhog.Generic.Sql ()
import Database.PostgreSQL.Simple.FromField (FromField, fromField)
import Database.PostgreSQL.Simple.ToField (ToField, toField)
import Database.PostgreSQL.Simple.Types (Binary (..), Identifier (..))

import Rhyolite.Schema (Json (..), SchemaName(..), LargeObjectId(..), HasId (..), Id (..))
import Rhyolite.Backend.Schema.TH (makePersistFieldNewtype)
import Rhyolite.Backend.Schema.Class (DerivedEntity, DerivedEntityHead, DefaultKeyId, toIdData, fromIdData)

instance ToField SchemaName where
  toField (SchemaName t) = toField (Identifier t)

deriving instance PrimitivePersistField SchemaName

instance NeverNull SchemaName

instance PersistField LargeObjectId where
  persistName _ = "LargeObjectId"
  toPersistValues (LargeObjectId n) = toPersistValues n
  fromPersistValues pv = do
    (x, pv') <- fromPersistValues pv
    return (LargeObjectId x, pv')
  dbType _ _ = DbTypePrimitive
    (DbOther $ OtherTypeDef [Left "oid"]) -- From https://www.postgresql.org/docs/current/static/lo-funcs.html
    False -- Not nullable
    Nothing -- No default value
    Nothing -- No parent table reference

deriving instance PrimitivePersistField LargeObjectId

instance NeverNull LargeObjectId

instance (ToJSON a, FromJSON a) => PersistField (Json a) where
  --TODO: Should this include the name of the underlying type
  persistName _ = "Json"
  toPersistValues (Json a) = toPersistValues (encode a)
  fromPersistValues vs = do
    (r, vs') <- fromPersistValues vs
    Just r' <- return $ decode' r
    return (Json r', vs')
  dbType p (Json a) = dbType p (encode a)

instance (ToJSON a, FromJSON a) => PrimitivePersistField (Json a) where
  toPrimitivePersistValue p (Json a) = toPrimitivePersistValue p (encode a)
  fromPrimitivePersistValue p v = runIdentity $ do
    Just r <- return $ decode' $ fromPrimitivePersistValue p v
    return (Json r)

instance ToJSON a => ToField (Json a) where
  toField (Json j) = toField $ Binary $ encode j

instance NeverNull (Json a)

instance (Typeable a, FromJSON a) => FromField (Json a) where
  fromField f mb = do
    (Binary v) <- fromField f mb
    let ev = eitherDecode' v
    case ev of
      Left err -> fail err
      Right v' -> return $ Json v'

fromDerivedId :: DerivedEntity v => Id v -> Id (DerivedEntityHead v)
fromDerivedId = Id . unId

toDerivedId :: DerivedEntity v => Id (DerivedEntityHead v) -> Id v
toDerivedId = Id . unId

toId :: forall a. DefaultKeyId a => DefaultKey a -> Id a
toId = Id . toIdData (Proxy :: Proxy a)

fromId :: forall a. DefaultKeyId a => Id a -> DefaultKey a
fromId = fromIdData (Proxy :: Proxy a) . unId

deriving instance NeverNull (IdData a) => NeverNull (Id a) -- A redundant constraint warning is expected here

instance (PersistField (DefaultKey a), DefaultKeyId a) => PersistField (Id a) where
  persistName = persistName
  toPersistValues = toPersistValues . fromId
  fromPersistValues vs = do
    (a, vs') <- fromPersistValues vs
    return (toId a, vs')
  dbType p _ = dbType p (undefined :: DefaultKey a)

instance (PrimitivePersistField (DefaultKey a), DefaultKeyId a) => PrimitivePersistField (Id a) where
  toPrimitivePersistValue p = toPrimitivePersistValue p . fromId
  fromPrimitivePersistValue p = toId . fromPrimitivePersistValue p

makePersistFieldNewtype ''SchemaName
