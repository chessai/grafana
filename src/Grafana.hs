{-# language
        BangPatterns
      , BlockArguments
      , DeriveFoldable
      , DeriveFunctor
      , DeriveGeneric
      , DeriveTraversable
      , DerivingStrategies
      , GeneralizedNewtypeDeriving
      , LambdaCase
      , OverloadedStrings
      , RecordWildCards 
  #-}

module Grafana
  ( ColumnSort(..)
  , Dashboard(..)
  , GraphiteQuery(..)
  , Gauge(..)
  , Graph(..)
  , Sparkline(..)
  , UnitFormat(..)
  , Panel(..)
  , PanelStyles(..)
  , PathComponent(..)
  , RGBA(..)
  , Row(..)
  , SortOrder(..)
  , StyleThresholds(..)
  , Table(..)
  , Templating(..)
  , TimeAmount(..)
  , TimeRange(..)
  , TimeUnit(..)

  , columns
  , defaultDashboard
  , defaultStyles
  , defaultGauge
  , defaultSparkline
  , getDashboardJSON
  , maxDashboardWidth
  , move
  
  , rowPanel
  , graphPanel
  , tablePanel
  , textPanel
  , singlestatPanel
  ) where

import Data.Aeson (ToJSON(..), FromJSON(..))
import Data.Aeson (Value(..), (.=), object)
import Data.Aeson.Encode.Pretty (encodePretty)
import Data.ByteString (ByteString)
import Data.Char (isAlphaNum)
import Data.Coerce (coerce)
import Data.List.NonEmpty (NonEmpty)
import Data.Maybe (isJust, maybeToList)
import Data.Text (Text)
import Data.Word (Word8)
import GHC.Generics (Generic)

import qualified Data.Aeson as AE
import qualified Data.ByteString.Lazy as BL
import qualified Data.List.NonEmpty as NE
import qualified Data.Text as T

tshow :: Show a => a -> Text
tshow = T.pack . show
{-# inlineable tshow #-} -- not exported, should inline anyway

optionalField :: ToJSON a => Text -> Maybe a -> [(Text,AE.Value)]
optionalField key = \case
  Nothing -> []
  Just x -> [ key .= x ]

data Templating = Templating
  { templatingOptions :: NonEmpty Text
  , templatingName :: !Text
  , templatingLabel :: !Text
  , templatingQuery :: !GraphiteQuery
  , templatingAllValue :: !(Maybe Text)
  } deriving stock (Eq, Read, Show)

instance ToJSON Templating where
  toJSON t = object $
    [ "datasource" .= String "Graphite"
    , "includeAll" .= isJust (templatingAllValue t)
    , "type" .= String "query"
    , "regex" .= optionsRegex (templatingOptions t)
    , "name" .= templatingName t
    , "label" .= Null
    , "current" .= object
        [ "text" .= firstOption
        , "value" .= firstOption
        ]
    , "definition" .= query
    , "query" .= query
    , "options" .= Array mempty
    , "tagsQuery" .= String ""
    , "tags" .= Array mempty
    , "useTags" .= False
    , "hide" .= (0 :: Int)
    , "multi" .= False
    , "refresh" .= (2 :: Int)
    , "tagValuesQuery" .= String ""
    ]
    <> optionalField "allValue" (templatingAllValue t)
    where
      query = serializeQuery (templatingQuery t)
      firstOption = NE.head (templatingOptions t)

optionsRegex :: NonEmpty Text -> Text
optionsRegex options = "/"
  <> T.intercalate "|" (stripInvalidChars <$> NE.toList options)
  <> "/"

data UnitFormat
  = PercentUnitFormat
  | PercentFormat
  | DBmFormat
  | SecondsFormat
  | MillisecondsFormat
  | BpsFormat
  deriving stock (Eq, Generic, Read, Show)

instance ToJSON UnitFormat where
  toJSON = \case
    PercentFormat -> "percent"
    PercentUnitFormat -> "percentunit"
    DBmFormat -> "dBm"
    SecondsFormat -> "s"
    MillisecondsFormat -> "ms"
    BpsFormat -> "bps"

  {-
instance ToJSON PanelType where
  toJSON = \case
    GraphPanel -> "graph"
    SinglestatPanel -> "singlestat"
    TablePanel -> "table"
    HeatmapPanel -> "heatmap"
    AlertListPanel -> "alertlist"
    DashboardListPanel -> "dashboardlist"
    TextPanel -> "text"
    RowPanel -> "row"
-}
data GridPos = GridPos
  { panelWidth :: !Int
  , panelHeight :: !Int
  , panelXPosition :: !Int
  , panelYPosition :: !Int
  } deriving stock (Eq, Generic, Read, Show)

instance ToJSON GridPos where
  toJSON (GridPos w h x y) =
    object
      [ "w" .= w
      , "h" .= h
      , "x" .= x
      , "y" .= y
      ]

data Column = Column
  { columnLabel :: !Text
  , columnValue :: !Text
  } deriving stock (Eq, Generic, Read, Show)

instance ToJSON Column where
  toJSON (Column label value) =
    object
      [ "text" .= String label
      , "value" .= String value
      ]

columns :: [Text] -> [Column]
columns = fmap (\name -> Column (T.toTitle name) (T.toLower name))

newtype PanelColumns = PanelColumns (Maybe [Column])
  deriving stock (Eq, Generic, Read, Show)

instance ToJSON PanelColumns where
  toJSON (PanelColumns x) = case x of
    Nothing -> Array mempty
    Just xs -> toJSON xs

data RGBA
  = RGBA !Word8 !Word8 !Word8 !Double
  | RGB !Word8 !Word8 !Word8
  deriving stock (Eq, Generic, Read, Show)

instance ToJSON RGBA where
  toJSON (RGBA r g b a) = String $
    "rgba(" <>
      tshow r <> ", " <>
      tshow g <> ", " <>
      tshow b <> ", " <>
      tshow a <> ")"
  toJSON (RGB r g b) = String $
    "rgb(" <>
      tshow r <> ", " <>
      tshow g <> ", " <>
      tshow b <> ")"

newtype StyleThresholds a = StyleThresholds [a]
  deriving stock (Generic, Read, Show)
  deriving newtype (Eq, ToJSON, FromJSON)
  deriving newtype (Functor, Foldable)

instance Traversable StyleThresholds where
  traverse f = fmap StyleThresholds . traverse f . coerce
  {-# inline traverse #-}

data SortOrder
  = Ascending
  | Descending
  deriving stock (Eq, Generic, Read, Show)

data ColumnSort = ColumnSort !Int !SortOrder
  deriving stock (Eq, Generic, Read, Show)

data Gauge = Gauge
  { minValue :: !Int
  , maxValue :: !Int
  , thresholdMarkers :: !Bool
  , thresholdLabels :: !Bool
  } deriving stock (Eq, Generic, Read, Show)

defaultGauge :: Gauge
defaultGauge = Gauge
  { minValue = 0
  , maxValue = 100
  , thresholdMarkers = True
  , thresholdLabels = False
  }

instance ToJSON Gauge where
  toJSON g = object
    [ "minValue" .= minValue g
    , "maxValue" .= maxValue g
    , "thresholdMarkers" .= thresholdMarkers g
    , "thresholdLabels" .= thresholdLabels g
    , "show" .= True
    ]

data Sparkline = Sparkline
  { fillColor :: !RGBA
  , full :: !Bool
  , lineColor :: !RGBA
  } deriving stock (Eq, Generic, Read, Show)

defaultSparkline :: Sparkline
defaultSparkline = Sparkline
  { fillColor = RGBA 31 118 189 0.18
  , full = False
  , lineColor = RGB 31 120 193
  }

instance ToJSON Sparkline where
  toJSON s = object
    [ "fillColor" .= fillColor s
    , "full" .= full s
    , "lineColor" .= lineColor s
    , "show" .= True
    ]

data PanelStyles = PanelStyles
  { alias :: !Text
  , colorMode :: !Text
  , colors :: [RGBA]
  , columnsSort :: !(Maybe ColumnSort)
  , decimals :: !Int
  , fontsize :: !Int
  , styleThresholds :: !(StyleThresholds Double)
  , styleUnit :: !(Maybe UnitFormat)
  , transparent :: !Bool
  , gauge :: !(Maybe Gauge)
  , colorBackground :: !Bool
  , colorValue :: !Bool
  , sparkline :: !(Maybe Sparkline)
  } deriving stock (Eq, Generic, Read, Show)

defaultStyles :: PanelStyles
defaultStyles = PanelStyles
  { alias = ""
  , colorMode = "cell"
  , colors = []
  , columnsSort = Nothing
  , decimals = 2
  , fontsize = 80
  , styleThresholds = StyleThresholds []
  , styleUnit = Nothing
  , transparent = False
  , gauge = Nothing
  , colorBackground = True
  , colorValue = False
  , sparkline = Nothing
  }

instance ToJSON PanelStyles where
  toJSON o = object
    [ "alias" .= alias o
    , "colorMode" .= colorMode o
    , "colors" .= colors o
    , "decimals" .= decimals o
    , "unit" .= String "short"
    , "type" .= String "number"
    , "pattern" .= String "/.*/"
    , "thresholds" .= fmap tshow (styleThresholds o)
    , "unit" .= styleUnit o
    ]

instance ToJSON ColumnSort where
  toJSON (ColumnSort n sortOrder) = object
    [ "col" .= n
    , "desc" .= (sortOrder == Descending)
    ]

rowToPairs :: Row -> [(Text, AE.Value)]
rowToPairs (Row t) = [ "type" .= String "row", "title" .= t ]

singlestatToPairs :: Singlestat -> [(Text, AE.Value)]
singlestatToPairs (Singlestat {..}) =
    [ "type" .= String "singlestat"
    , "title" .= singlestatTitle
    , "targets" .= makeTargets singlestatQueries
    , "valueFontSize" .= singlestatFontSize
    , "mode" .= singlestatMode
    , "format" .= singlestatUnit
    , "thresholds" .= singlestatThresholds
    , "colorBackground" .= singlestatColorBackground
    , "colorValue" .= singlestatColorValue
    , "colors" .= singlestatColors
    ]
    <> optionalField "gauge" singlestatGauge
    <> optionalField "sparkline" singlestatSparkline

tableToPairs :: Table -> [(Text, AE.Value)]
tableToPairs (Table {..}) =
    [ "type" .= String "table" 
    , "title" .= tableTitle
    , "targets" .= makeTargets tableQueries
    , "columns" .= tableColumns
    , "valueFontSize" .= tableFontSize
    , "styles" .= tableStyles
    , "transform" .= tableTransform
    ]
    <> optionalField "sort" tableSort

graphToPairs :: Graph -> [(Text, AE.Value)]
graphToPairs (Graph {..}) =
  [ "type" .= String "graph"
  , "title" .= graphTitle
  , "targets" .= makeTargets graphQueries
  , "nullPointMode" .= graphNullPointMode
  ]
  <> case graphUnit of
       Nothing -> []
       Just su -> 
         [ "yaxes" .=
           [ object
               [ "format" .= su
               , "label" .= Null
               , "logBase" .= Number 1
               , "max" .= Null
               , "min" .= Null
               , "show" .= True
               ]
           , object
               [ "format" .= String "short"
               , "label" .= Null
               , "logBase" .= Number 1
               , "max" .= Null
               , "min" .= Null
               , "show" .= True
               ]
           ]
         ]

rowPanel :: Row -> GridPos -> Panel
rowPanel = Panel . rowToPairs

graphPanel :: Graph -> GridPos -> Panel
graphPanel = Panel . graphToPairs

tablePanel :: Table -> GridPos -> Panel
tablePanel = Panel . tableToPairs

textPanel :: TextPanel -> GridPos -> Panel
textPanel = Panel . textPanelToPairs

singlestatPanel :: Singlestat -> GridPos -> Panel
singlestatPanel = Panel . singlestatToPairs


textPanelToPairs :: TextPanel -> [(Text, AE.Value)]
textPanelToPairs (TextPanel {..}) =
  [ "type" .= String "text"
  , "title" .= textTitle
  , "content" .= textContent
  , "transparent" .= textIsTransparent
  ]

data Panel = Panel
  { panelObject :: [(Text, AE.Value)]
  , panelGridPos :: GridPos
  } 
  deriving stock (Eq, Generic, Read, Show)

instance ToJSON Panel where
  toJSON p = object $
    ( "gridPos" .= panelGridPos p ) : panelObject p

data TimeUnit
  = Seconds
  | Minutes
  | Hours
  | Days
  deriving stock (Eq, Generic, Read, Show)

data TimeAmount = Interval !Int !TimeUnit
  deriving stock (Eq, Generic, Read, Show)

displayTimeAmount :: TimeAmount -> Text
displayTimeAmount (Interval n units) =
  case units of
    Seconds -> (tshow n <> "s")
    Minutes -> (tshow n <> "m")
    Hours -> (tshow n <> "h")
    Days -> (tshow n <> "d")

instance ToJSON TimeAmount where
  toJSON = String . displayTimeAmount

data TimeRange = TimeRange
  { rangeFrom :: !TimeAmount
  , rangeTo :: !(Maybe TimeAmount)
  } deriving stock (Eq, Generic, Read, Show)

instance ToJSON TimeRange where
  toJSON range =
    object
      [ "from" .= ("now-" <> displayTimeAmount (rangeFrom range))
      , "to" .=
          case rangeTo range of
            Nothing -> "now"
            Just r -> "now-" <> displayTimeAmount r
      ]

maxDashboardWidth :: Int
maxDashboardWidth = 24

data Dashboard = Dashboard
  { dashboardIdentifier :: !(Maybe Int)
  , dashboardUid :: !(Maybe Text)
  , dashboardTitle :: !Text
  , dashboardTime :: !TimeRange
  , dashboardRefresh :: !TimeAmount
  , dashboardVersion :: !Int
  , dashboardPanels :: [Panel]
  , dashboardTemplating :: [Templating]
  , dashboardLinks :: [Link]
  , dashboardTags :: [Text]
  } deriving stock (Eq, Generic, Read, Show)

instance ToJSON Dashboard where
  toJSON g = object $
    [ "panels" .= dashboardPanels g
    , "title" .= dashboardTitle g
    , "time" .= dashboardTime g
    , "templating" .= object
        [ "list" .= dashboardTemplating g
        ]
    , "links" .= dashboardLinks g
    , "tags" .= dashboardTags g
    ] <> maybeToList (("uid" .=) <$> dashboardUid g)

defaultDashboard :: Dashboard
defaultDashboard = Dashboard
  { dashboardIdentifier = Nothing
  , dashboardUid = Nothing
  , dashboardTitle = "New dashboard"
  , dashboardPanels = []
  , dashboardTime = TimeRange (Interval 1 Hours) Nothing
  , dashboardRefresh = Interval 5 Seconds
  , dashboardVersion = 1
  , dashboardTemplating = []
  , dashboardLinks = []
  , dashboardTags = []
  }

data Target = Target
  { refId :: !Text
  , targetVal :: !Text
  } deriving (Eq, Generic, Read, Show)

instance ToJSON Target where
  toJSON g =
    object
      [ "refId" .= refId g
      , "target" .= targetVal g
      ]

data Link = Link
  { tags :: [Text]
  , title :: !Text
  } deriving (Eq, Generic, Read, Show)

instance ToJSON Link where
  toJSON g =
    object
      [ "asDropdown" .= True
      , "icon" .= String "external link"
      , "tags" .= tags g
      , "title" .= title g
      , "type" .= String "dashboards"
      ]

makeTargets :: [GraphiteQuery] -> [Target]
makeTargets = zipWith
  (\refid query -> Target refid (serializeQuery query))
  refids
  where
    refids = fmap (\n -> "I" <> tshow n) [(0 :: Int) ..]

data Table = Table
  { tableTitle :: Text
  , tableQueries :: [GraphiteQuery]
  , tableColumns :: [Column]
  , tableSort :: Maybe ColumnSort
  , tableFontSize :: Int
  , tableStyles :: TableStyles
  , tableTransform :: TableTransform
  }

data NullPointMode = Connected

instance ToJSON NullPointMode where
  toJSON Connected = String "connected"

data Graph = Graph
  { graphTitle :: Text
  , graphQueries :: [GraphiteQuery]
  , graphNullPointMode :: NullPointMode
  , graphUnit :: Maybe UnitFormat
  }

data TextPanel = TextPanel
  { textTitle :: Text
  , textContent :: Text
  , textIsTransparent :: Bool
  }

data Singlestat = Singlestat
  { singlestatTitle :: Text
  , singlestatQueries :: [GraphiteQuery]
  , singlestatFontSize :: Int
  , singlestatUnit :: UnitFormat
  , singlestatColorBackground :: Bool
  , singlestatColorValue :: Bool
  , singlestatColors :: [RGBA]
  , singlestatMode :: ColorMode
  , singlestatGauge :: Maybe Gauge
  , singlestatSparkline :: Maybe Sparkline
  }
  deriving (Eq, Show)

newtype Row = Row Text

data GraphiteQuery
  = HighestCurrent GraphiteQuery !Int
  | AverageSeriesWithWildcards GraphiteQuery !Int
  | AliasSub GraphiteQuery !Text !Text
  | Alias GraphiteQuery !Text
  | Avg GraphiteQuery
  | Absolute GraphiteQuery
  | Offset GraphiteQuery !Int
  | Metric [PathComponent Text]
  | LiteralQuery !Text
  deriving stock (Eq, Read, Show)

serializeQuery :: GraphiteQuery -> Text
serializeQuery = \case
  HighestCurrent q n ->
    "highestCurrent(" <> serializeQuery q <> "," <> tshow n <> ")"
  AverageSeriesWithWildcards q n ->
    "averageSeriesWithWildcards(" <> serializeQuery q <> "," <> tshow n <> ")"
  AliasSub q a b ->
    "aliasSub(" <> serializeQuery q <> ",'" <> a <> "','" <> b <> "')"
  Alias q a ->
    "alias(" <> serializeQuery q <> ",'" <> a <> "')"
  Avg q ->
    "avg(" <> serializeQuery q <> ")"
  Absolute q ->
    "absolute(" <> serializeQuery q <> ")"
  Offset q n ->
    "offset(" <> serializeQuery q <> "," <> tshow n <> ")"
  Metric xs ->
    T.intercalate "." (serializePathComponent . fmap stripInvalidChars <$> xs)
  LiteralQuery t ->
    t

stripInvalidChars :: Text -> Text
stripInvalidChars = T.filter (\c -> isAlphaNum c || c == '-' || c == '_')

data PathComponent a
  = Anything
  | Variable !Text
  | Literal a
  | OneOf [a]
  deriving stock (Eq, Ord, Read, Show)
  deriving stock (Functor, Foldable, Traversable)

serializePathComponent :: PathComponent Text -> Text
serializePathComponent = \case
  Anything -> "*"
  Variable v -> "$" <> v
  Literal name -> name
  OneOf xs -> "{" <> T.intercalate "," xs <> "}"

getDashboardJSON :: Dashboard -> ByteString
getDashboardJSON = BL.toStrict . encodePretty

move :: Int -> Int -> Panel -> Panel
move dx dy panel =
  let
    GridPos w h x y = panelGridPos panel
    newPos = GridPos w h (x + dx) (y + dy)
  in
    panel { panelGridPos = newPos }
