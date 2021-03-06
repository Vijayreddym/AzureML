# Copyright (c) 2015-2016 Microsoft Corporation
# All rights reserved.
#   
# The MIT License (MIT)
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#   
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.



#' Publish a function as a Microsoft Azure Web Service.
#'
#' Publish a function to Microsoft Azure Machine Learning as a web service. The web service created is a standard Azure ML web service, and can be used from any web or mobile platform as long as the user knows the API key and URL. The function to be published is limited to inputs/outputs consisting of lists of scalar values or single data frames (see the notes below and examples). Requires a zip program to be installed (see note below).
#'
#' @export
#'
#' @inheritParams refresh
#' @inheritParams workspace
#' @param fun a function to publish; the function must have at least one argument.
#' @param name name of the new web service; ignored when \code{serviceId} is specified (when updating an existing web service).
#' 
#' @param inputSchema either a list of \code{fun} input parameters and their AzureML types formatted as \code{list("arg1"="type", "arg2"="type", ...)}, or an example input data frame when \code{fun} takes a single data frame argument; see the note below for details.
#' 
#' @param outputSchema list of \code{fun} outputs and AzureML types, formatted as \code{list("output1"="type", "output2"="type", ...)}, optional when \code{inputSchema} is an example input data frame.
#' 
#' @param export optional character vector of variable names to explicitly export in the web service for use by the function. See the note below.
#' @param noexport optional character vector of variable names to prevent from exporting in the web service.
#' @param packages optional character vector of R packages to bundle in the web service, including their dependencies.
#' @param version optional R version string for required packages (the version of R running in the AzureML Web Service).
#' @param serviceId optional Azure web service ID; use to update an existing service (see Note below).
#' @param host optional Azure regional host, defaulting to the global \code{management_endpoint} set in \code{\link{workspace}}
#' @param data.frame \code{TRUE} indicates that the function \code{fun} accepts a data frame as input and returns a data frame output; automatically set to \code{TRUE} when \code{inputSchema} is a data frame.
#' @param .retry number of tries before failing
#' 
#' @return A data.frame describing the new service endpoints, cf. \code{\link{endpoints}}. The output can be directly used by the \code{\link{consume}} function.
#'  
#' @note 
#' \bold{Data Types}
#' 
#' AzureML data types are different from, but related to, R types. You may specify the R types \code{numeric, logical, integer,} and \code{character} and those will be specified as AzureML types \code{double, boolean, int32, string}, respectively.
#'
#' \bold{Input and output schemas}
#'
#' Function input must be:
#' \enumerate{
#' \item named scalar arguments with names and types specified in \code{inputSchema}
#' \item one or more lists of named scalar values
#' \item a single data frame when \code{data.frame=TRUE} is specified; either explicitly specify the column names and types in \code{inputSchema} or provide an example input data frame as \code{inputSchema}
#' }
#' Function output is always returned as a data frame with column names and types specified in \code{outputSchema}. See the examples for example use of all three I/O options.
#'
#' \bold{Updating a web service}
#'
#' Leave the \code{serviceId} parameter undefined to create a new AzureML web service, or specify the ID of an existing web service to update it, replacing the function, \code{inputSchema}, \code{outputSchema}, and required R pacakges with new values. The \code{name} parameter is ignored \code{serviceId} is specified to update an existing web service.
#' 
#' The \code{\link{updateWebService}} function is nearly an alias for \code{\link{publishWebService}}, differing only in that the \code{serviceId} parameter is required by \code{\link{updateWebService}}.
#'
#' The \code{publishWebService} function automatically exports objects required by the function to a working environment in the AzureML machine, including objects accessed within the function using lexical scoping rules. Use the \code{exports} parameter to explicitly include other objects that are needed. Use \code{noexport} to explicitly prevent objects from being exported.
#' 
#' Note that it takes some time to update the AzureML service on the server.  After updating the service, you may have to wait several seconds for the service to update.  The time it takes will depend on a number of factors, including the complexity of your web service function.
#' 
#' \bold{External zip program required}
#' 
#' The function uses \code{\link[utils]{zip}} to compress information before transmission to AzureML. To use this, you need to have a zip program installed on your machine, and this program should be available in the path. The program should be called \code{zip} otherwise R may not find it. On windows, it is sufficient to install RTools (see \url{https://cran.r-project.org/bin/windows/Rtools/})
#' 
#' @seealso \code{\link{endpoints}}, \code{\link{discoverSchema}}, \code{\link{consume}} and \code{\link{services}}.
#' @family publishing functions
#'
#' @example inst/examples/example_publish.R
#' @importFrom jsonlite toJSON
#' @importFrom uuid UUIDgenerate
#' @importFrom curl new_handle handle_setheaders handle_setopt
publishWebService <- function(ws, fun, name,
                              inputSchema, outputSchema, 
                              `data.frame` = FALSE,
                              export = character(0), 
                              noexport = character(0), 
                              packages,
                              version = "3.1.0", 
                              serviceId, 
                              host = ws$.management_endpoint,
                              .retry = 3)
{
  # Perform validation on inputs
  stopIfNotWorkspace(ws)
  if(!zipAvailable()) stop(zipNotAvailableMessage)
  if(is.character(fun)) stop("You must specify 'fun' as a function, not a character")
  if(!is.function(fun)) stop("The argument 'fun' must be a function.")
  if(!is.list(inputSchema)) stop("You must specify inputSchema as either a list or a data.frame")
  
  if(missing(serviceId) && as.character(match.call()[1]) == "updateWebService")
    stop("updateWebService requires that the serviceId parameter is specified")
  if(missing(name) && !missing(serviceId)) name = "" # unused in this case
  if(missing(serviceId)) serviceId = gsub("-", "", UUIDgenerate(use.time = TRUE))
  publishURL = sprintf("%s/workspaces/%s/webservices/%s",
                       host, ws$id, serviceId)
  # Make sure schema matches function signature
  if(inputSchemaIsDataframe(inputSchema)){
    `data.frame` <- TRUE
  }
  if(`data.frame`) {
    function_output <- match.fun(fun)(head(inputSchema))
    inputSchema <- azureSchema(inputSchema)
    if(missing(outputSchema)) {
      if(is.data.frame(function_output) || is.list(function_output)) {
        outputSchema <- azureSchema(function_output)
      } else {
        outputSchema <- azureSchema(list(ans = class(function_output)))
      }
    }
  } else {
    # not a data frame
    inputSchema <- azureSchema(inputSchema)
    if(missing(outputSchema)) {
      function_output <- match.fun(fun)(inputSchema)
      outputSchema <- azureSchema(function_output)[[1]]
    } else {
      outputSchema <- azureSchema(outputSchema)
    }
    
  } 

  ### Get and encode the dependencies
  
  if(missing(packages)) packages=NULL
  exportenv = new.env()
  .getexports(substitute(fun), 
              exportenv, 
              parent.frame(), 
              good = export, 
              bad = noexport
  )
  
  ### Assign required objects in the export environment
  
  assign("..fun", fun, envir = exportenv)
  assign("..output_names", names(outputSchema), envir = exportenv)
  assign("..data.frame", `data.frame`, envir = exportenv)
  
  zipString = packageEnv(exportenv, packages = packages, version = version)
  
  ### Build the body of the request
  
  req = list(
    Name = name,
    Type = "Code",
    CodeBundle = list(
      InputSchema  = inputSchema,
      OutputSchema = outputSchema,
      Language     = "R-3.1-64",
      SourceCode   = wrapper,
      ZipContents  = zipString
    )
  )
  body = charToRaw(
    paste(toJSON(req, auto_unbox = TRUE), collapse = "\n")
  )
  h = new_handle()
  httpheader = list(
    Authorization = paste("Bearer ", ws$.auth),
    `Content-Type` = "application/json",
    Accept = "application/json"
  )
  opts = list(
    post = TRUE,
    postfieldsize = length(body),
    postfields = body,
    customrequest = "PUT"
  )
  handle_setheaders(h, .list = httpheader)
  handle_setopt(h, .list = opts)
  r = try_fetch(publishURL, handle = h, .retry = .retry)
  result = rawToChar(r$content)
  if(r$status_code >= 400) stop(result)
  newService = fromJSON(result)
  
  ### refresh the workspace cache
  refresh(ws, "services")
  
  ### Use discovery functions to get endpoints for immediate use
  endpoints(ws, newService["Id"])
}


#' @rdname publishWebService
#' @export
updateWebService = publishWebService


