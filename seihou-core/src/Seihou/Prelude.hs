{-# LANGUAGE PackageImports #-}

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
    view,
    over,
    set,
    (^.),
    (.~),
    (%~),
    (&),
    lens,
    Lens',
    Getting,
    ASetter,

    -- * FilePath
    FilePath,
    (</>),
  )
where

import "containers" Data.Map.Strict (Map)
import "containers" Data.Set (Set)
import "effectful-core" Effectful (Dispatch (Dynamic), DispatchOf, Eff, Effect, IOE, MonadIO, liftIO, runEff, type (:>), type (:>>))
import "effectful-core" Effectful.Dispatch.Dynamic (EffectHandler, HasCallStack, interpret, reinterpret, send)
import "filepath" System.FilePath ((</>))
import "generic-lens" Data.Generics.Labels ()
import "lens" Control.Lens (ASetter, Getting, Lens', lens, over, set, view, (%~), (&), (.~), (^.))
import "text" Data.Text (Text)
