#' Update a reactable instance
#'
#' `updateReactable()` updates a reactable instance within a Shiny application.
#'
#' @param outputId The Shiny output ID of the `reactable` instance.
#' @param data Table data. A data frame or matrix.
#'
#'   `data` should have the same columns as the original table data.
#'   When updating `data`, the selected rows, expanded rows, and current page
#'   will reset unless explicitly specified. All other state will persist,
#'   including sorting, filtering, and grouping state.
#' @param selected Selected rows. Either a numeric vector of row indices,
#'   or `NA` to deselect all rows.
#' @param expanded Expanded rows. Either `TRUE` to expand all rows, or `FALSE`
#'   to collapse all rows.
#' @param page The current page. A single, positive integer.
#' @param meta Custom table metadata. Either a named list with new values, or `NA`
#'   to clear all metadata. New values are merged into the current metadata, so only
#'   the values specified in `meta` will be updated.
#' @param session The Shiny session object. Defaults to the current Shiny session.
#' @return None
#'
#' @examples
#' # Run in an interactive R session
#' if (interactive()) {
#'
#' library(shiny)
#' library(reactable)
#'
#' data <- MASS::Cars93[, 1:7]
#'
#' ui <- fluidPage(
#'   actionButton("select_btn", "Select rows"),
#'   actionButton("clear_btn", "Clear selection"),
#'   actionButton("expand_btn", "Expand rows"),
#'   actionButton("collapse_btn", "Collapse rows"),
#'   actionButton("page_btn", "Change page"),
#'   selectInput("filter_type", "Filter type", unique(data$Type), multiple = TRUE),
#'   reactableOutput("table")
#' )
#'
#' server <- function(input, output) {
#'   output$table <- renderReactable({
#'     reactable(
#'       data,
#'       filterable = TRUE,
#'       searchable = TRUE,
#'       selection = "multiple",
#'       details = function(index) paste("Details for row:", index)
#'     )
#'   })
#'
#'   observeEvent(input$select_btn, {
#'     # Select rows
#'     updateReactable("table", selected = c(1, 3, 5))
#'   })
#'
#'   observeEvent(input$clear_btn, {
#'     # Clear row selection
#'     updateReactable("table", selected = NA)
#'   })
#'
#'   observeEvent(input$expand_btn, {
#'     # Expand all rows
#'     updateReactable("table", expanded = TRUE)
#'   })
#'
#'   observeEvent(input$collapse_btn, {
#'     # Collapse all rows
#'     updateReactable("table", expanded = FALSE)
#'   })
#'
#'   observeEvent(input$page_btn, {
#'     # Change current page
#'     updateReactable("table", page = 3)
#'   })
#'
#'   observe({
#'     # Filter data
#'     filtered <- if (length(input$filter_type) > 0) {
#'       data[data$Type %in% input$filter_type, ]
#'     } else {
#'       data
#'     }
#'     updateReactable("table", data = filtered)
#'   })
#' }
#'
#' shinyApp(ui, server)
#' }
#'
#' @export
updateReactable <- function(outputId, data = NULL, selected = NULL, expanded = NULL,
                            page = NULL, meta = NULL, session = NULL) {
  if (is.null(session)) {
    if (requireNamespace("shiny", quietly = TRUE)) {
      session <- shiny::getDefaultReactiveDomain()
    }
    if (is.null(session)) {
      # Not in an active Shiny session
      return(invisible(NULL))
    }
  }

  if (!is.character(outputId)) {
    stop("`outputId` must be a character string")
  }
  outputId <- session$ns(outputId)

  dataKey <- NULL
  if (!is.null(data)) {
    if (!is.data.frame(data) && !is.matrix(data)) {
      stop("`data` must be a data frame or matrix")
    }
    dataKey <- digest::digest(data)
    # Reset selected, expanded, and page state by default
    selected <- if (is.null(selected)) NA else selected
    expanded <- if (is.null(expanded)) FALSE else expanded
    page <- if (is.null(page)) 1 else page
  }

  if (!is.null(selected)) {
    if (!is.numeric(selected) && !is.na(selected)) {
      stop("`selected` must be numeric or NA")
    }
    selected <- stats::na.omit(selected)
    # Convert to 0-based indexing
    selected <- as.list(as.integer(selected) - 1)
  }

  if (!is.null(expanded) && !is.logical(expanded)) {
    stop("`expanded` must be TRUE or FALSE")
  }

  if (!is.null(page)) {
    if (!is.numeric(page) || length(page) != 1 || page <= 0) {
      stop("`page` must be a single, positive integer")
    }
    # Convert to 0-based indexing
    page <- as.integer(page - 1)
  }

  if (!is.null(meta)) {
    if (!isNamedList(meta) && !is.na(meta)) {
      stop("`meta` must be a named list or NA")
    }
    # Allow empty lists, but don't serialize them as an empty array, []
    if (identical(meta, list())) {
      meta <- NULL
    }
  }

  # Get JS evals for meta. Exclude other props like data - although data could
  # potentially have JS() code within list-columns, it's not supported by reactable(), and
  # JS() code just ends up as a string.
  jsEvals <- htmlwidgets::JSEvals(list(meta = meta))
  if (length(jsEvals) == 0) {
    jsEvals <- NULL
  }

  newState <- filterNulls(list(
    data = data,
    dataKey = dataKey,
    selected = selected,
    expanded = expanded,
    page = page,
    meta = meta,
    jsEvals = jsEvals
  ))

  if (length(newState) > 0) {
    session$sendCustomMessage(sprintf("__reactable__%s", outputId), newState)
  }
}

#' Get the state of a reactable instance
#'
#' `getReactableState()` gets the state of a reactable instance within a Shiny application.
#'
#' @param outputId The Shiny output ID of the `reactable` instance.
#' @param name Character vector of state value(s) to get. Values must be one of `"page"`,
#'   `"pageSize"`, `"pages"`, `sorted`, or `"selected"`. If unspecified, all values will
#'   be returned.
#' @param session The Shiny session object. Defaults to the current Shiny session.
#' @return If `name` is specified, one of the following values:
#'
#'   - `page`: the current page
#'   - `pageSize`: the page size
#'   - `pages`: the number of pages
#'   - `sorted`: the sorted columns - a named list of columns with values of `"asc"` for
#'      ascending order or `"desc"` for descending order, or `NULL` if no columns are sorted
#'   - `selected`: the selected rows - a numeric vector of row indices, or `NULL` if no rows are selected
#'
#'  If `name` contains more than one value, `getReactableState()` returns a named list of
#'  the specified values.
#'
#'  If `name` is unspecified, `getReactableState()` returns a named list containing all values.
#'
#'  If the table has not been rendered yet, `getReactableState()` returns `NULL`.
#'
#' @examples
#' # Run in an interactive R session
#' if (interactive()) {
#'
#' library(shiny)
#' library(reactable)
#' library(htmltools)
#'
#' ui <- fluidPage(
#'   actionButton("prev_page_btn", "Previous page"),
#'   actionButton("next_page_btn", "Next page"),
#'   reactableOutput("table"),
#'   verbatimTextOutput("table_state"),
#'   uiOutput("selected_row_details")
#' )
#'
#' server <- function(input, output) {
#'   output$table <- renderReactable({
#'     reactable(
#'       MASS::Cars93[, 1:5],
#'       showPageSizeOptions = TRUE,
#'       selection = "multiple",
#'       onClick = "select"
#'     )
#'   })
#'
#'   output$table_state <- renderPrint({
#'     state <- req(getReactableState("table"))
#'     print(state)
#'   })
#'
#'   observeEvent(input$prev_page_btn, {
#'     # Change to the previous page
#'     page <- getReactableState("table", "page")
#'     if (page > 1) {
#'       updateReactable("table", page = page - 1)
#'     }
#'   })
#'
#'   observeEvent(input$next_page_btn, {
#'     # Change to the next page
#'     state <- getReactableState("table")
#'     if (state$page < state$pages) {
#'       updateReactable("table", page = state$page + 1)
#'     }
#'   })
#'
#'   output$selected_row_details <- renderUI({
#'     selected <- getReactableState("table", "selected")
#'     req(selected)
#'     details <- MASS::Cars93[selected, -c(1:5)]
#'     tagList(
#'       h2("Selected row details"),
#'       tags$pre(
#'         paste(capture.output(print(details, width = 1200)), collapse = "\n")
#'       )
#'     )
#'   })
#' }
#'
#' shinyApp(ui, server)
#' }
#'
#' @export
getReactableState <- function(outputId, name = NULL, session = NULL) {
  if (is.null(session)) {
    if (requireNamespace("shiny", quietly = TRUE)) {
      session <- shiny::getDefaultReactiveDomain()
    }
    if (is.null(session)) {
      # Not in an active Shiny session
      return(NULL)
    }
  }
  if (!is.character(outputId)) {
    stop("`outputId` must be a character string")
  }

  getState <- function(outputId, name) {
    # NOTE: input IDs must always come first to work with Shiny modules
    session$input[[sprintf("%s__reactable__%s", outputId, name)]]
  }

  props <- c("page", "pageSize", "pages", "sorted", "selected")
  if (!is.null(name)) {
    if (!is.character(name) || any(!name %in% props)) {
      stop(paste("`name` values must be one of", paste(sprintf('"%s"', props), collapse = ", ")))
    }
    if (length(name) == 1) {
      return(getState(outputId, name))
    } else {
      props <- name
    }
  }

  state <- stats::setNames(
    lapply(props, function(prop) {
      getState(outputId, prop)
    }),
    props
  )

  if (length(filterNulls(state)) == 0) {
    return(NULL)
  }

  state
}
