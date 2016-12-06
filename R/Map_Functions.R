##MAP FUNCTIONS
#---------------------------------------------------------------------------
# DATA PROCESSING FUNCTIONS
#---------------------------------------------------------------------------

#' Extract a query from a list of queries and filter to desired output.
#'
#' Extract the desired table from the structure produced by
#' \code{\link{parse_mi_output}}.  Optionally, perform some filtering
#' and transformation on the data.  (XXX: We need _way_ more
#' information here.  What gets filtered and transformed, and how does
#' it work?)
#'
#' @param batchq The structure containing the GCAM results (produced
#' by \code{\link{parse_mi_output}}).
#' @param query The name of the table to extract; i.e., the name of
#' one of the queries cointained in the GCAM output.
#' @param scen The name of the scenario.  Partial matches are allowed.
#' @param filters A named vector of filtering criteria in the form
#' \code{c(header1=value1, header2=value2,...)}.  Headers are the
#' names of columns in the data frame.  If aggregating data, use the
#' value "Aggregate".  (XXX: Needs further explanation!)
#' @param func Operation to apply to the aggregated data.  (XXX: Does
#' this mean that this option is active only when using the
#' "Aggregate" option above?)
#' @export
process_batch_q<-function(batchq, query, scen, filters, func=sum){

  qdata<-as.data.frame(batchq[[query]])

  #Filter for scenario; allow partial lookup
  #Bug: if partial has multiple matches, will return multiple scenarios
  qdata<-qdata[grepl(scen, qdata$scenario),]

  #Get years and aggregate value if applicable
  years<-grep("(X1)|(X2)", names(qdata), value=T)
  ag<-names(filters[filters[names(filters)]=="Aggregate"]) #Super clunky

  nms<-!(names(qdata) %in% years| names(qdata) %in% ag)

  #Filter to query of interest using filters
  for (name in names(filters)){
    if (filters[[name]]=="Aggregate"){
      qdata<-aggregate(qdata[years], by=qdata[nms], FUN=func)
      qdata[[ag]]<-"All"
    }
    else{
      qdata<-qdata[qdata[[name]]==filters[[name]],]
    }
  }

  return(qdata)

}

###TODO - modify to search for appropriate lookup, province, drop files in directory.
#' Match GCAM ID to region using data from a lookup table.
#'
#' We match by ID number to avoid problems with variant spellings and the like.
#' @param datatable A table of results produced by \code{\link{process_batch_q}}
#' @param lookupfile File containing the region lookup table.  XXX: we
#' need to provide a mechanism for users to use the data installed
#' internally in the package.
#' @param provincefile File containing the province lookup table, if
#' applicable. XXX: Same comment as above
#' @param drops File containing a list of regions to drop, if
#' applicable.  XXX: Same comment as above.
#' @return Input table modified to include a GCAM ID for reach region.
#' @export
addRegionID<-function(datatable, lookupfile, provincefile='none', drops='none') {
  if (provincefile != 'none'){
    datatable<-translateProvince(datatable, provincefile)
  }

  if (drops != 'none'){
    datatable<-dropRegions(datatable, drops)
  }

  lookuptable<-read.csv(lookupfile, strip.white=T, stringsAsFactors = F)

  #Differentiate region-Region issue
  if ("Region" %in% names(datatable)){
    rgn<-"Region"
  } else{
    rgn<-"region"
  }

  finaltable<-merge(datatable, lookuptable, by.x=rgn, by.y=colnames(lookuptable)[1], all.y=TRUE )

  ## Regions that weren't in the original table will show as NA.  Zero
  ## them out and give them a sensible unit.
  finaltable$Units[is.na(finaltable$Units)] <- finaltable$Units[1] # units will usually be all the same
  finaltable[is.na(finaltable)] <- 0                               # set all remaining NA values to zero.
  colnames(finaltable)[ncol(finaltable)]<-'id'
  finaltable$id<-as.character(finaltable$id)


  #Add null vector row to end to account for GCAM region 0
  nullvec <- rep(NA, ncol(finaltable))

  finaltable<-rbind(finaltable, nullvec)
  finaltable[nrow(finaltable),rgn] <- '0'                     # region 0 name (should be something more descriptive?)
  finaltable$id[nrow(finaltable)]<-'0'

  return(finaltable)
}

translateProvince<-function(datatable, provincefile){
  ### Replace province abbreviations with full province names
  ### to ensure matching with GCAM map names.
  ### Inputs:
  ###   datatable - data frame of query from batch query CSV.
  ###   provincefile - string; path to file with abbreviations and full names of regions.
  ### Outputs:
  ###   datatable - datatable modified so that abbreviations are now full names.

  provincetable<-read.csv(provincefile, strip.white=T)

  #Differentiate region-Region issue
  if ("Region" %in% names(datatable)){
    rgn<-"Region"
  } else{
    rgn<-"region"
  }

  datatable$rgn<-as.character(datatable$rgn)
  provincetable$province<-as.character(provincetable$province)
  provincetable$province.name<-as.character(provincetable$province.name)

  datatable$rgn<-ifelse(is.na(provincetable$province.name[match(datatable$rgn, provincetable$province)]),
                           datatable$rgn,
                           provincetable$province.name[match(datatable$rgn, provincetable$province)])

  return(datatable)
}

dropRegions<-function(datatable, drops){
  ### Drop regions listed in drops file from data frame.
  ### Inputs:
  ###   datatable - a data frame of query from batch query CSV
  ###   drops - string; path to file containing regions to be dropped
  ### Outputs:
  ###   datatable - updated data frame with regions dropped.

  dr<-read.csv(drops, strip.white=T, header=F)
  dr<-as.character(dr$V1)

  regcols<-grepl("egion", names(datatable)) #Find instances of "region" or "Region" columns

  datatable[regcols]<-lapply(datatable[regcols], function(x) replace(x, x %in% dr, NA)) #Replace drop col values with NA

  datatable<-na.omit(datatable) #Remove rows containing NA

  return(datatable)
}

#---------------------------------------------------------------------------
# MAPPING UTILS
#---------------------------------------------------------------------------
get_bbox_polys<-function(dataset, bbox=EXTENT_WORLD){
  ### Modifies map data to include only polygons that lie partially within
  ### bounding box.
  ### Inputs:
  ###   dataset - data frame of map geometry
  ###   bbox - numeric vector (long_min, long_max, lat_min, lat_max)
  ### Outputs:
  ###   newdata - data with only polygons that are at least partially in
  ###           bounding box

    dplyr::filter(dataset, in_range(long, bbox[1], bbox[2]), in_range(lat, bbox[3], bbox[4]))
}

## in_range - Test a vector to see which values are in the interval [a,b]
## params: x:  vector to test
##       a,b:  interval bounds. can be int or numeric; a<=b
in_range<-function(x, a, b){
    x>=a & x<=b
}

gen_grat<-function(bbox=EXTENT_WORLD,longint=20,latint=30){
  ### Generate graticule (long/lat lines) given bbox
  ### Inputs:
  ###   bbox - numeric vector (long_min, long_max, lat_min, lat_max)
  ###   longint - interval between longitude lines
  ###   latint - interval between latitude lines
  ### Outputs:
  ###   grat - dataframe describing of latitude and longitude lines
  ###         spaced at specified intervals

### TODO: We could probably realize some savings here by
### precalculating and caching graticules for some commonly-used
### configurations.


  #Generate graticule as sp matrix object
  lons=seq(bbox[1],bbox[2],by=longint)
  lats=seq(bbox[3],bbox[4],by=latint)

  grat<-graticule::graticule(lons,lats,xlim=range(lons),ylim=range(lats))

  #Convert to ggplot2-friendly format
  grat<-ggplot2::fortify(grat)

  return(grat)

}

#' Calculate legend breaks (intervals to put labels on legend scale)
#'
#' Given a minimum and maximum value, and number of breaks, calculate
#' evenly-spaced break values.
#'
#' @param maxval Largest value in the scale
#' @param minval Smallest value in the scale
#' @param nbreak Number of break points
#' @param nsig Number of significant digits to display in the legend.
calc.breaks <- function(maxval, minval=0, nbreak=5, nsig=3)
{
    step <- (maxval-minval)/(nbreak-1)
    seq(0,maxval, by=step) %>% signif(nsig)
}
calc.breaks.map<-function(mapdata, colname, nbreaks=4, zero.min=TRUE){
  ### Calculate legend 
  ### Inputs:
  ###   mapdata - data frame of geometry and scenario data
  ###   colname - column name of interest from which to calculate legend intervals
  ###   nbreaks - number of intervals
  ###   zero.min- force minimum value of scale to zero
  ### Outputs:
  ###   breaks - vector of values at which to include legend label


    vals <- as.numeric(mapdata[[colname]])

    max_dat <- max(vals, na.rm = T)
    if(zero.min)
        min_dat = 0
    else
        min_dat <- min(vals, na.rm= T)

    calc.breaks(max_dat, min_dat, nbreaks)
}

#-----------------------------------------------------------------
# COLOR PALETTE FUNCTIONS
#-----------------------------------------------------------------

#' Generate a color palette for categorical data.
#'
#' Generate a palette with a specified number of entries.  This
#' function uses a ramp function to extend the palettes from
#' \code{\link{RColorBrewer}} so they can handle a larger number of
#' entries.
#'
#' @param n Number of entries desired for the palette
#' @param pal Name of the palette to base the new palette on. See
#' \code{RColorBrewer} for the palettes available.
#' @param na.val Color to use for the null region
#' @export
qualPalette<- function(n = 31, pal = 'Set3', na.val = 'grey50'){
  colors<-colorRampPalette(RColorBrewer::brewer.pal(8, pal))(n)
  colors<-setNames(colors, as.character(1:n))
  colors["0"]<-na.val

  return(colors)
}


#-----------------------------------------------------------------
# MAPPING FUNCTIONS
#-----------------------------------------------------------------
# coord_GCAM: This function unifies the ggplot2 and ggalt coordinate systems to make use
#   of both of them, depending on the projection needed. Can be used with any ggplot2 map object.
#   If projection is orthographic, will use ggplot2 coord_map functionality. If projection is not
#   orthographic, will use ggalt coord_proj functionality.
#
# Arguments
#   proj - the projection. proj4 string or pre-defined variable in diag_header.R
#   orientation - Use if using orthographic projection
#   extent - Vector of lat/lon limits c(lat0,lat1,lon0,lon1)
#   parameters - additional parameters corresponding to coord_map ggplot2 function
#   inverse ?
#   degrees - Units for lat/longitude ?
#   ellps.default - default ellipse to use with projection ?
#
# Usage: as add-on function to a ggplot2 object. Example:
#  ggplot()+
#   geom_polygon(data, aes(x,y,group))+
#   coord_GCAM(proj)

coord_GCAM <- function(proj = NULL, orientation = NULL, extent = NULL, ..., parameters = NULL, inverse=FALSE,
                       degrees=TRUE, ellps.default="sphere"){

  if (is.null(proj)){
    # Default proj4 pstring for default GCAM projection (Robinson)
    proj <- paste0(c("+proj=robin +lon_0=0 +x_0=0 +y_0=0",
                     "+ellps=WGS84 +datum=WGS84 +units=m +nodefs"),
                   collapse = " ")
  }

  if (is.null(parameters)){
    params <- list(...)
  } else {
    params <- parameters
  }

  # Default extent is EXTENT_WORLD (-180,180,-90,90)
  if (is.null(extent)){
    xlim <- c(-180,180)
    ylim <- c(-90,90)
  } else{
    xlim <- c(extent[1], extent[2])
    ylim <- c(extent[3], extent[4])
  }

  # Use ggproto object defined in ggplot2 package if using orthographic map projection
  if(grepl("ortho", proj)){
    ggproto(NULL, ggplot2::CoordMap,
            projection = proj,
            orientation = orientation,
            limits = list(x = xlim, y = ylim),
            params = params
    )
  } else{
    # Otherwise use ggproto object defined in ggalt package for default GCAM projections
    ggproto(NULL, ggalt::CoordProj,
            proj = proj,
            inverse = inverse,
            ellps.default = ellps.default,
            degrees=degrees,
            limits = list(x = xlim, y = ylim),
            params = list()
    )
  }

}


# theme_GCAM: Default GCAM theme function. Can be used with any ggplot2 object.
#   Derives from ggplot2 black and white theme function (theme_bw)
#
# Arguments:
#   base_size: Base font size
#   base_family: Base font type
#   legend: T or F; whether to include a legend with default legend formatting.
#
# Usage: As add-on function to any ggplot2 object.
theme_GCAM <- function(base_size = 11, base_family="", legend=F){

  if (legend==F){
    theme_bw(base_size = base_size, base_family= base_family) %+replace%
      theme(
        panel.border = element_rect(color = LINE_COLOR, fill = NA),
        panel.background = PANEL_BACKGROUND,
        panel.grid = PANEL_GRID,
        axis.ticks = AXIS_TICKS,
        axis.text = AXIS_TEXT,
        legend.position='none'
      )
  }

  else if (legend==T){
    theme_bw(base_size = base_size, base_family= base_family) %+replace%
      theme(
        panel.border = element_rect(color = LINE_COLOR, fill = NA),
        panel.background = PANEL_BACKGROUND,
        panel.grid = PANEL_GRID,
        axis.ticks = AXIS_TICKS,
        axis.text = AXIS_TEXT,
        legend.key.size = unit(0.75, "cm"),
        legend.text = element_text(size = 10),
        legend.title = element_text(size=12, face="bold"),
        legend.position = LEGEND_POSITION,
        legend.key=element_rect(color='black')
      )
  }

}




##-----------------------------------------------------------------
## MAPS
##-----------------------------------------------------------------

#' Primary GCAM mapping function. Can handle categorical or continuous data.
#'
#' This function produces a map visualization of a data set containing
#' GCAM output data.  The required argument is a data frame of GCAM
#' results by region.  The functions \code{\link{parse_mi_output}} and
#' \code{\link{process_batch_q}} produce suitable data frames.
#'
#' For specifying the projection you can use any Proj4 string.
#' Projections specified this way are computed using
#' \code{\link{ggalt::coord_proj}}.  For convenience, this package
#' defines the following proj4 strings:
#' \itemize{
#'   \item \code{\link{eck3}} - Eckert III
#'   \item \code{\link{wintri}} - Winkel-Tripel
#'   \item \code{\link{robin}} - Robinson
#'   \item \code{\link{na_aea}} - Albers equal area (North America)
#'   \item \code{\link{ch_aea}} - Albers equal area (China)
#' }
#'
#' For orthographic projections, we compute the projection using the
#' \code{\link{mapproj::coord_map}} function.  To get this projection
#' pass the \code{\link{ortho}} symbol as the \code{proj} argument.
#' You will then need to pass a vector in the \code{orientation}
#' argument.  We have defined the following fequently used orientation
#' vectors:
#' \itemize{
#'   \item \code{\link{ORIENTATION_AFRICA}} - Africa
#'   \item \code{\link{ORIENTATION_LA}} - Latin America
#'   \item \code{\link{ORIENTATION_SPOLE}} - South Pole
#'   \item \code{\link{ORIENTATION_NPOLE}} - North Pole
#' }
#'
#' The \code{extent} argument gives the bounding box of the area to be
#' plotted.  Its format is \code{c(lon.min, lon.max, lat.min,
#' lat.max)}.  For convenience we have defined the following
#' frequently used map extents:
#' \itemize{
#'    \item \code{\link{EXTENT_WORLD}} - Entire world
#'    \item \code{\link{EXTENT_USA}} - Continental United States
#'    \item \code{\link{EXTENT_CHINA}} - China
#'    \item \code{\link{EXTENT_AFRICA}} - Africa
#'    \item \code{\link{EXTENT_LA}} - Latin America
#' }
#' 
#' @param mapdata The data frame containing both geometric data (lat, long, id)
#' and regional metadata.  This is the only mandatory variable. If used alone,
#' will produce the default map.
#' @param col If plotting categorical/contiuous data, the name of the column to
#' plot.  Will automatically determine type of style of plot based on type of
#' data (numeric or character).
#' @param proj Map projection to use in the display map.  This should be a proj4
#' string, except for a few special cases.  There are also symbols defined for
#' some frequently used projections (e.g. \code{\link{robin}} or
#' \code{\link{na_aea}}).
#' @param extent Bounding box for the display map
#' @param orientation The orientation vector.  This is only needed for
#' projections that don't use proj4.  Projections using proj4 encode this
#' information in their proj4 string.
#' @param title Text to be displayed as the plot title
#' @param legend Boolean flag: True = display map legend; False = do not display
#' legend
#' @param colors Vector of colors to use in the color scale.  If NULL, then
#' default color scheme will be used.
#' @param qtitle Text to be displayed as the legend title.
#' @param limits Vector of two values giving the range of the color bar in the
#' legend.  c(min,max)
#' @param colorfcn If plotting categorical data, the function used to generate a
#' colorscheme when colors are not provided (if NULL, use qualPalette).  If
#' \code{colors} is specified, or if the data being plotted is numerical, this
#' argument will be ignored.
#' @examples
#'
#' ##Plot a map of GCAM regions; color it with a palette based on RColorBrewer's
#' "Set3" palette.
#'   map_32_wo_Taiwan<-rgdal::readOGR(system.file('extdata/rgn32', 'GCAM_32_wo_Taiwan_clean.geojson',
#'                                                package=gcammaptools))
#'   map_32_wo_Taiwan.fort<-ggplot2::fortify(map_32_wo_Taiwan, region="GCAM_ID")
#'   mp1<-plot_GCAM(map_32_wo_Taiwan.fort, col = 'id', proj = eck3, colorfcn=qualPalette)
#'
#'   ## Plot oil consumption by region
#'   tables<-parse_mi_output(fn = system.file('extdata','sample-batch.csv',package=gcammaptools))
#'   prim_en<-process_batch_q(tables, "primary_energy", "Reference", c(fuel="a oil"))
#'   prim_en<-addRegionID(prim_en, file.path(basedir.viz,
#'                                 system.file('extdata/rgn32', 'lookup.txt', package=gcammaptools),
#'                                 system.file('extdata/rgn32', 'drop-regions.txt', package=gcammaptools))
#'   mp2<-plot_GCAM(map_primen, col = "X2050", colors = c("white", "red"), title="Robinson World", qtitle="Oil Consumption, 2050", legend=T)
#' @export
plot_GCAM <- function(mapdata, col = NULL, proj=robin, extent=EXTENT_WORLD, orientation = NULL,
                      title = NULL, legend = F, colors = NULL, qtitle=NULL, limits=NULL,
                      colorfcn=NULL, ...){

  # Generate graticule (latitude/longitude lines) and clip map to extent specified.
  grat<-gen_grat()
  mappolys <- get_bbox_polys(dataset = mapdata)


  #Plot graticule and polygons
  mp<-ggplot()+
    geom_path(data=grat,aes(long,lat,group=group,fill=NULL),color=LINE_GRAT)+
    geom_polygon(data=mappolys, aes_string("long","lat",group="group",fill=col), color=LINE_COLOR)

  # If a column name is specified, add a color gradient or categorical colors
  if (!is.null(col)){

      if(is.numeric(mappolys[[col]])) {
      # Instructions for color gradient
      # Calculate legend label increments ('breaks')
      if(is.null(limits))
        breaks <- calc.breaks.map(mappolys, col)
      else
        breaks <- calc.breaks(limits[2])

      # Use default colors if none specified
      if(is.null(colors))
        colors <- DEFAULT_CHOROPLETH

      # Add color scale to map
      mp <- mp+
        scale_fill_gradientn(name=qtitle, colors=colors, values=NULL, guide=GUIDE, space=SPACE,
                             na.value=NA_VAL, breaks=breaks,limits=limits,
                             labels=breaks)

    } else {
      # Instructions for categorical map
      # Use default color scheme and color function if none specified
      if (is.null(colors)){
        if(is.null(colorfcn)){
          colorfcn <- qualPalette
        }
        colors<-colorfcn(n = length(unique(mappolys[[col]])), ...)
      }

      # Add color scale to map
      mp <- mp+
        scale_fill_manual(values=colors,name=qtitle)
    }
  } else{
    # If no data is being plotted, use default color scale
    mp <- mp +
      geom_polygon(data=mappolys, aes_string("long","lat",group="group",fill=col),fill=RGN_FILL, color=LINE_COLOR)
  }

  # Project map and add theme and labels
  mp <- mp +
    coord_GCAM(proj=proj,orientation=orientation,extent=extent)+
    theme_GCAM(legend=legend)+
    labs(title=title, x=XLAB, y=YLAB)

  return(mp)
}
