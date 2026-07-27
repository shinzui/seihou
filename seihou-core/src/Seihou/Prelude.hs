{-# LANGUAGE PackageImports #-}
{-# LANGUAGE PatternSynonyms #-}

module Seihou.Prelude
  ( -- * Text
    Text,

    -- * Containers
    Map,
    Set,

    -- * Effectful core
    Eff,
    runEff,
    type (:>),
    type (:>>),
    IOE,
    Effect,
    Dispatch (Dynamic),
    type DispatchOf,
    MonadIO,
    liftIO,

    -- * Effectful dynamic dispatch
    send,
    interpret,
    reinterpret,
    HasCallStack,
    EffectHandler,

    -- * Lens
    module Control.Lens,

    -- * Generics
    Generic,

    -- * Bifunctor
    first,

    -- * FilePath
    FilePath,
    (</>),
  )
where

import "base" Data.Bifunctor (first)
-- Every record type in the project derives Generic, both because the house
-- style requires it and because generic-lens synthesises #label lenses from
-- the Generic representation. Re-exporting it here keeps the derive clauses
-- import-free.
import "base" GHC.Generics (Generic)
import "containers" Data.Map.Strict (Map)
import "containers" Data.Set (Set)
import "effectful-core" Effectful (Dispatch (Dynamic), DispatchOf, Eff, Effect, IOE, MonadIO, liftIO, runEff, type (:>), type (:>>))
import "effectful-core" Effectful.Dispatch.Dynamic (EffectHandler, HasCallStack, interpret, reinterpret, send)
import "filepath" System.FilePath ((</>))
-- Re-export the whole lens API. PackageImports pins the package so that
-- `Control.Lens` unambiguously means the `lens` package's module.
--
-- Deliberately absent: Data.Generics.Labels. Its IsLabel instance is an
-- orphan, and orphan instances propagate transitively, so importing it here
-- would force the generic-lens interpretation of #label onto every module in
-- the project. Each module that uses #label imports it individually instead.
--
-- Four names are hidden. Each collides with a name seihou already has in
-- scope, and none of the four is a lens combinator seihou has any use for:
--
--   (.=)      collides with Data.Aeson's (.=), used unqualified by the
--             hand-written ToJSON instances in eleven modules. The lens (.=)
--             is the MonadState assignment operator; seihou uses effectful's
--             State with `modify` and never needs it.
--   argument  collides with Options.Applicative.argument, imported openly by
--             Seihou.CLI.Commands. The lens `argument` is a Setter over a
--             Profunctor's argument position.
--   List      collides with the `List` constructor of Seihou.CLI.Commands's
--             Command type. The lens `List` is an IsList pattern synonym.
--   Context   collides with the `Context` constructor of the same type. The
--             lens `Context` is the indexed store comonad.
import "lens" Control.Lens hiding (Context (..), argument, (.=), pattern List)
import "text" Data.Text (Text)
