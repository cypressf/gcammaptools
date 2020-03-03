# output.r
#
# The main file that produces output from standard functions

library(raster)
library(sf)
library(rgdal)
library(rgeos)
library(ggplot2)

#' Single import function for compatible data types.
#'
#' Imports available for sf objects, spatial data frames, ESRI Shapefiles, or
#' GeoJSON files.
#'
#' @param shape_path Input full path string to shape
#' @param shape_obj Pass shape object in directly instead of path
#' @param raster_path Input full path string to raster
#' @param  raster_obj Pass raster object in directly instead of path
#' @param  dpi
#' @param  output_file
#' @param  simplify
#' @return A ggplot object
#' @export
create_map <- function(shape_path = NULL, shape_obj = NULL, raster_path = NULL, raster_obj = NULL, raster_col = NULL,
                       dpi = 150, output_file = NULL, simplify = FALSE)
{
   # shape_path = "data/tm_world_borders_simpl-0.3.shp"
   # raster_path = "data/wc2.0_10m_tavg_01.tif"

    error <- "test"

    tryCatch(
    {
        # Shape loading
        if(is.null(shape_path))
        {
            if(!is.null(shape_obj))
                shape <- shape_obj
            else
                error <- "both shape null"
        }
        else if(is.null(shape_obj))
        {
            shape <- rgis::import_shapefile(shape_path, quiet = TRUE)
        }
        else
        {
            error <- "both shape NOT null"
        }

        # if(class(shape) == "sf")
        #     error <- "true"
        # else
        #     error <- "false"

        # Raster loading
        if(is.null(raster_path))
        {
            if(!is.null(raster_obj))
                raster <- raster_obj
            else
                error <- "both raster null"
        }
        else if(is.null(raster_obj))
        {
            raster <- rgis::import_raster(raster_path)
        }
        else
        {
            error <- "both raster NOT null"
        }

        # if(class(raster) == "raster")
        #     error <- "true"
        # else
        #     error <- "false"

        # Compare projections
        if(raster::compareCRS(shape, raster))
            error <- "proj ok" # same projection
        else
        {
            shape <- st_transform(shape, crs(raster))
            compare_result <- raster::compareCRS(shape, raster)
            error <- compare_result
        }

        # Convert raster
        raster_df <- as.data.frame(raster, xy = TRUE)

        # Raster operations
        if(!is.null(raster_col))
          raster_df <- dplyr::mutate(raster_df, value = raster_df[[raster_col]])
        else
          error <- "No raster column defined"

        raster_min <- minValue(raster)
        raster_max <- maxValue(raster)
        raster_layers <- nlayers(raster)

        browser()

        output <- ggplot() + ggplot2::geom_sf(data = shape) +
          geom_raster(data=raster_df, aes(x=x, y=y, fill=value), alpha = 0.85) +
          coord_sf() + gcammaptools::theme_GCAM()

    },
    warning = function(war)
    {
        # warning handler picks up where error was generated
        error <- war
    },
    error = function(err)
    {
        # error handler picks up where error was generated
        error <- err
    })

  #  plot(raster)
  #  plot(shape)

    return(output)
}

#
#
#
#     path <- "e:/repos/github/gcammap/data/ne_50m_coastline/ne_50m_coastline.shp"
#     # Code for reading in and determining shape
#     shape <- sf::st_read(path)
#
#     # Code for reading in and determining raster
#
#     ggplot() +
#         geom_polygon(data = shape_fortified, aes( x = long, y = lat, group = group), fill="#69b3a2", color="white") +
#         theme_void()
#
#     tryCatch(
#     {
#         # Input validation code here
#         else
#         {
#             if(input$mapVar == "tas")
#                 patternFile <- globalTempPatterns[[input$mapPattern]]
#             else
#                 patternFile <- globalPrecipPatterns[[input$mapPattern]]
#             results <- hector::fetchvars(hcores[[input$mapCore]], 1900:2100)
#             tgav_hector <- dplyr::filter(results, variable == "Tgav")
#             pattern <- readRDS(patternFile)
#             coordinates <- pattern$coordinate_map
#             incProgress(1/2, detail = paste("Loading pattern, downscaling"))
#             for(i in 1:length(coordinates$lon))
#             {
#                 if(coordinates$lon[i] > 180)
#                     coordinates$lon[i] <- coordinates$lon[i] - 360
#             }
#
#             mapname <- paste("map", 1, sep="")
#             hector_annual_gridded <- fldgen::pscl_apply(pattern$annual_pattern, as.vector(tgav_hector$value+15))
#             hector_annual_gridded_t <- t(hector_annual_gridded)
#
#             if(input$mapVar == "tas")
#             {
#                 if(input$input_map_compare)
#                 {
#                     mapFill <- "\u0394 Temperature \u00B0C"
#                     mapVar <- "deltaTemp"
#                 }
#                 else
#                 {
#                     mapFill <- "Temperature \u00B0C"
#                     mapVar <- "Temp"
#                 }
#                 mapPalette <- "RdYlBu"
#                 mapDirection <- -1
#
#                 combined_data <- dplyr::mutate(
#                     coordinates,
#                     Temp = round(hector_annual_gridded_t[, as.numeric(input$mapYear) - 1899], 2),
#                     deltaTemp = round(hector_annual_gridded_t[, as.numeric(input$mapYear) -
#                                                                   1899] - hector_annual_gridded_t[, 1], 2),
#                     Lon = round(lon, 2),
#                     Lat = round(lat, 2),
#                     Neg = ifelse(deltaTemp < 0, TRUE, FALSE)
#
#                 )
#             }

#              mapDirection <- 1
#              mapPalette <- "Purples"
#              # mapVar <- "Precip"
#              # if(input$input_map_compare)
#              combined_data <- dplyr::mutate(coordinates, Precip = round(1000*hector_annual_gridded_t[, as.numeric(input$mapYear)-1899], 4),
#                                             deltaPrecip = round(1000*(hector_annual_gridded_t[, as.numeric(input$mapYear)-1899] - hector_annual_gridded_t[, 1]), 4),
#                                             Lon=round(lon, 2), Lat=round(lat,2), Neg = ifelse(deltaPrecip < 0, TRUE, FALSE))
#              #  else
#              #  combined_data <- dplyr::mutate(coordinates, Precip = round(1000*hector_annual_gridded_t[, as.numeric(input$mapYear)-1899], 4), Lon=round(lon, 2), Lat=round(lat,2))
#              # combined_data$Neg <- ifelse(combined_data$Precip < 0, FALSE, TRUE)
#
#             combined_data <- dplyr::select(combined_data, -c(lat, lon, colnum))

#
#              combined_data <- dplyr::filter(combined_data, Lat >= lat_min, Lat <= lat_max, Lon >= lon_min, Lon <= lon_max)
#
#
#             mapWorld <- ggplot2::borders("world",  ylim=c(lat_min, lat_max), xlim=c(lon_min, lon_max)) #  colour="black", col="white",, fill="gray100"
#
#             ggplotMap <- ggplot2::ggplot() +
#              mapWorld +
#              ggplot2::geom_tile(data = combined_data, ggplot2::aes_string(x="Lon", y = "Lat", fill=mapVar)) +
#              # ggplot2::geom_point(data = combined_data, ggplot2::aes(x = Lon, y = Lat, color = Neg, alpha = 0.5)) +
#              ggplot2::coord_fixed(ratio = 1) +
#              ggplot2::scale_fill_distiller(palette = mapPalette,type = "div", direction = mapDirection, na.value = "Gray" ) +
#              #viridis::scale_fill_viridis(direction = 1, option = "E" ) +
#              ggplot2::labs(x="\u00B0Longitude", y="\u00B0Latitude", title = paste0(input$mapCore, " - ", input$mapYear), fill = mapFill) +
#              ggplot2::scale_y_continuous(limits=c(lat_min, lat_max), expand = c(0, 0), breaks=seq(-90,90,30))+
#              ggplot2::scale_x_continuous(limits=c(lon_min, lon_max), expand = c(0, 0), breaks=seq(-180,180,30))
#
#             localPlot <- plotly::ggplotly(p = ggplotMap)
#             plotly::layout(p=localPlot, yaxis = list(tickformat = "\u00B0C", dtick = 10))
#
#             output[[mapname]] <- plotly::renderPlotly(localPlot)
#             incProgress(1/1, detail = "Map loaded.")
#             Sys.sleep(0.25)
#             shinyjs::show(id = 'map-div')
#
