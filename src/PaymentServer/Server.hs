{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedStrings #-}

-- | This module exposes a Servant-based Network.Wai server for payment
-- interactions.
module PaymentServer.Server
  ( RedemptionConfig(RedemptionConfig)
  , paymentServerApp
  , makeMetricsMiddleware
  ) where

import Network.Wai.Middleware.Cors
  ( Origin
  , CorsResourcePolicy(corsOrigins, corsMethods, corsRequestHeaders)
  , simpleCorsResourcePolicy
  , cors
  )
import Servant
  ( Proxy(Proxy)
  , Server
  , Application
  , serve
  , (:>)
  , (:<|>)((:<|>))
  )
import Prometheus
  ( register
  )
import Servant.Prometheus
  ( monitorServant
  , meters
  )

import Web.Stripe.Client
  ( StripeConfig
  )

import PaymentServer.Processors.Stripe
  ( StripeAPI
  , stripeServer
  )
import PaymentServer.Redemption
  ( RedemptionConfig(RedemptionConfig)
  , RedemptionAPI
  , redemptionServer
  )
import PaymentServer.Metrics
  ( MetricsAPI
  , metricsServer
  )
import PaymentServer.Issuer
  ( Issuer
  )
import PaymentServer.Persistence
  ( VoucherDatabase
  )

-- | This is the complete type of the server API.
type PaymentServerAPI
  =    "v1" :> "stripe" :> StripeAPI
  :<|> "v1" :> "redeem" :> RedemptionAPI
  :<|> MetricsAPI

-- | Create a server which uses the given database.
paymentServer :: VoucherDatabase d => StripeConfig -> RedemptionConfig -> d -> Server PaymentServerAPI
paymentServer stripeConfig redemptionConfig database =
  stripeServer stripeConfig database
  :<|> redemptionServer redemptionConfig database
  :<|> metricsServer

paymentServerAPI :: Proxy PaymentServerAPI
paymentServerAPI = Proxy

-- | Create a Servant Application which serves the payment server API using
-- the given database.
paymentServerApp
  :: VoucherDatabase d
  => [Origin]              -- ^ A list of CORS Origins to accept.
  -> StripeConfig
  -> RedemptionConfig
  -> d
  -> Application
paymentServerApp corsOrigins stripeConfig redemptionConfig =
  let
    app = serve paymentServerAPI . paymentServer stripeConfig redemptionConfig
    withCredentials = False
    corsResourcePolicy = simpleCorsResourcePolicy
                         { corsOrigins = Just (corsOrigins, withCredentials)
                         , corsMethods = [ "POST" ]
                         , corsRequestHeaders = [ "Content-Type" ]
                         }
    cors' = cors (const $ Just corsResourcePolicy)
  in
    cors' . app


-- | Create middleware which captures metrics for the payment server app.
makeMetricsMiddleware :: IO (Application -> Application)
makeMetricsMiddleware = do
  meters <- register $ meters paymentServerAPI
  return $ monitorServant meters
