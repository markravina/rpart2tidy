
#' Turns rpart data into tibble
#'
#' This function is an alternative to rpart.plot and other graphing options for decision trees objects generated by rpart
#' @param rpart_object the name of the rpart object
#' @param text_size number, defaults to 4
#' @param node_spacing the vertical distance between nodes for purity and nodes for splits values. Defaults to 0.5
#' @return A list of three dataframes (or tibbles)
#' \enumerate{
#'    \item nodes.tbl has data for the main nodes
#'    \item linesegments.tbl has the data for connecting lines
#'    \item YES_NO.tbl has xy coordinates for small yes-no branching nodes
#' }


rpart2tidy <- function(rpart_object,text_size=4,node_spacing=0.5)
{

  node.df <- data.frame(rpart_object$frame)
  party_data <- partykit::as.party(rpart_object)

  node_kids <- data.frame(t(sapply(as.list(party_data$node), function(n) {
    if(is.null(n$kids)) c(n$id, NA, NA) else c(n$id, n$kids)}))) ## get the kids

  ## get the node depth

  node_depth <- vapply(seq(1:length(party_data)), function (x) grid::depth(party_data[[x]]), FUN.VALUE = numeric(1))
  node_width <- vapply(seq(1:length(party_data)), function (x) partykit::width(party_data[[x]]), FUN.VALUE = numeric(1))
  node_length <- vapply(seq(1:length(party_data)), function (x) length(party_data[[x]]), FUN.VALUE = numeric(1))


  yvals <- attr(x = rpart_object,which = "ylevels") ## get the numeric codes for yvals
  full_node.df <- data.frame("node_id"=rownames(node.df), "node_seq"=node_kids$X1,cbind(node.df[,c(1:5)],"depth"=node_depth,"width"=node_width,
                                                                                        "length"=node_length,node_kids),stringsAsFactors = FALSE)
  num_leaves <- length(rpart_object$frame$var[which(rpart_object$frame$var=="<leaf>")])
  full_node.df$x_position <- NA
  # full_node.df$y_position <- NA


  full_node.df$pos_node_val <- yvals[full_node.df$yval]
  ## paste together multiple negative var names for non-binary cases
  full_node.df$neg_node_val <- vapply(full_node.df$pos_node_val,
                                      function(x) paste(yvals[!yvals%in%x], collapse =" OR "), character(1))


  full_node.df$pos_node_count <- full_node.df$n - full_node.df$dev
  full_node.df$neg_node_count <- full_node.df$dev
  full_node.df$pos_node_perc <- round(full_node.df$pos_node_count/full_node.df$n*100,1)
  full_node.df$neg_node_perc <- round(full_node.df$neg_node_count/full_node.df$n*100,1)

  ## x positions for leaves
  ## assign integers based on node_number, ie., seq(1,num_leaves,1)
  ## and add a spacing variable seq(0,num_leaves-1,1) for a gap between leaves

    full_node.df <- full_node.df[order(as.numeric(full_node.df$node_seq)),]



  full_node.df$x_position[which(full_node.df$depth==0)] <-
    seq(1,num_leaves,1) + seq(0,num_leaves-1,1)


  ## x position for nodes -- first step:
  ## place lowest level in between the node's leaves
  ## using mean of x of leaves
  ## then loop down (or up) the tree to the root node
  ## node_sequence gives nodes in correct sequence for kids to parents
  node_sequence <- unlist(sapply(seq(1, max(node_depth),1), function (x) full_node.df$node_seq[which(full_node.df$depth==x)]))

  x_spot <- function (x) {
    mean(full_node.df$x_position[which(full_node.df$node_seq%in%node_kids[x,])], na.rm = TRUE)
  }


  for(i in seq_along(node_sequence)) {
    full_node.df$x_position[node_sequence[i]] <- x_spot(node_sequence[i])
  }

  ## get split values for split text labels

  splits.df <- data.frame(rownames(rpart_object$splits),rpart_object$splits[,c(1:2,4)],stringsAsFactors = FALSE)
  colnames(splits.df) <- c("var","count","direction","split_value")

  ## in order to match nodes in frame with 'real' values in splits
  ## we need to ignore surrogate and compete values
  ## that requires using counts of compete and surrogate nodes
  real_node.df <- node.df[which(!node.df$var=="<leaf>"),]

  real_node.df$split_no <- real_node.df$ncompete+real_node.df$nsurrogate+1
  split_index <- c(1,real_node.df$split_no) ## add 1 to get the first node
  split_index <- cumsum(split_index) ## cumsum to shift down for all the surrogate nodes at each level

  split_index <- utils::head(split_index, -1) ## removes last element
  splits_to_add.df <- splits.df[split_index,c("var","count","direction","split_value")]


  real_node.df <- cbind(real_node.df,splits_to_add.df)
  real_node.df <- real_node.df[,c("var","n","count","direction","split_value")]
  real_node.df$node_id <- rownames(real_node.df)



  ## for the attributes (x variables) get the classes
  var_type <- data.frame(attr(rpart_object$terms, "dataClasses"),stringsAsFactors = FALSE)
  var_type$var <- rownames(var_type)

  colnames(var_type) <- c("class","var")

  ## get text values for x vars, e.g. "male" and "female" not 0 and 1

  x_val_levels <- unlist(attr(x = rpart_object,which = "xlevels"))
  x_var_names <- names(attr(x = rpart_object,which = "xlevels"))
  x_val_frequencies <- unlist(lapply(1:length(attr(x = rpart_object,which = "xlevels")), function (x) length(attr(rpart_object,which = "xlevels")[[x]]) ))
  x_val_series <- rep(x_var_names,x_val_frequencies)
  x_val_index <- unlist(lapply(1:length(attr(x = rpart_object,which = "xlevels")), function (x) seq(1,(length(attr(rpart_object,which = "xlevels")[[x]])),1) ))


  x_vals.df <- data.frame("var"= x_val_series,"char_value" = x_val_levels, "split_value" = x_val_index, stringsAsFactors = FALSE)

  ## take out var and n from real_node.df to simplify dplyr::left_join
  real_node.df <- real_node.df[,c("node_id","count","split_value","direction")]


  full_node.df <- dplyr::left_join(full_node.df,real_node.df,by=c("node_id"))
  full_node.df$var <- as.character(full_node.df$var) ## just to avoid warning

  full_node.df <- dplyr::left_join(full_node.df,var_type,by=c("var"))

  full_node.df$direction_marker <- ifelse(full_node.df$direction==1,">","<")
  full_node.df$direction_marker <- ifelse(full_node.df$class=="character","is",full_node.df$direction_marker)

  ## mapvalues for character splits

  full_node.df <- dplyr::left_join(full_node.df,x_vals.df, by=c("var","split_value"))


  full_node.df$split_text <- paste(full_node.df$var,
                                   full_node.df$direction_marker,
                                   round(full_node.df$split_value,2))
  full_node.df$split_text <- ifelse(full_node.df$var=="<leaf>",NA,full_node.df$split_text)
  full_node.df$split_text <- ifelse(full_node.df$class=="character",paste(full_node.df$var,
                                                                          full_node.df$direction_marker,
                                                                          full_node.df$char_value),
                                    full_node.df$split_text)

  full_node.df$purity_text <- paste("total = ",full_node.df$n,
                                    "\n", full_node.df$pos_node_val, " = ", full_node.df$pos_node_count,
                                    " (",round(full_node.df$pos_node_perc,0),"%)",
                                    "\n", full_node.df$neg_node_val, " = ", full_node.df$neg_node_count,
                                    " (",round(full_node.df$neg_node_perc,0),"%)", sep="")

  depth_spacing <- 1

  node_spacing <- depth_spacing*node_spacing

  full_node.df$y_position_main_node <- full_node.df$depth*depth_spacing
  full_node.df$y_position_split <- full_node.df$y_position_main_node-node_spacing

  full_node.df$y_position_split <- ifelse(full_node.df$var=="<leaf>",NA,full_node.df$y_position_split)

  parent_kid.df <- tidyr::gather(node_kids, key = "key", value = "value", 2:3, na.rm = FALSE,
                          convert = FALSE, factor_key = FALSE)
  colnames(parent_kid.df)[c(1,3)] <- c("parent","kid")


  parent_kid.df <- parent_kid.df[,c(1,3)]
  parent_kid.df <- parent_kid.df[order(parent_kid.df$parent),]
  start_line <- rep("start_line",nrow(parent_kid.df)) ## need start and end markers for segments
  line_breaks <- rep("line_breaks",nrow(parent_kid.df))

  ## make it long to join withall the x and y values
  parent_kid_long <- c(rbind(start_line,parent_kid.df$parent,parent_kid.df$parent,parent_kid.df$kid,line_breaks))
  just_places.df <- full_node.df[,c("node_seq","x_position","y_position_main_node","y_position_split","direction")]
  just_places.df$node_seq <- as.character(just_places.df$node_seq)

  parent_kid_long.df <- data.frame("node_seq"=as.character(parent_kid_long), stringsAsFactors = FALSE)
  ## join the x and y values
  parent_kid_long_point.df <- dplyr::left_join(parent_kid_long.df,just_places.df,by="node_seq")

  ## leaves do NOT have a split, so use the main node
  parent_kid_long_point.df$y_position <- ifelse(is.na(parent_kid_long_point.df$y_position_split),parent_kid_long_point.df$y_position_main_node,parent_kid_long_point.df$y_position_split)

  ## find the midpoints
  mid_points <- which(parent_kid_long_point.df$node_seq=="start_line")
  parent_kid_long_point.df <- parent_kid_long_point.df[,c(1,2,6,5)]

  ## each "yes or no" node gets the x values of the subsequent node
  parent_kid_long_point.df$x_position[mid_points+2] <- parent_kid_long_point.df$x_position[mid_points+3]

  ## set y_position to zero for leaves
  parent_kid_long_point.df$y_position <- ifelse(is.na(parent_kid_long_point.df$direction)&!is.na(parent_kid_long_point.df$x_position),0,parent_kid_long_point.df$y_position)

  line_segments.df <- data.frame("node_seq"=parent_kid_long_point.df$node_seq,"x"=parent_kid_long_point.df$x_position,"y"=parent_kid_long_point.df$y_position,"direction"=parent_kid_long_point.df$direction)

  ## create end values for the segments -- spread the dataframe

  line_segments.df$x_end <- NA
  line_segments.df$x_end[mid_points+1] <- line_segments.df$x[mid_points+2]
  line_segments.df$y_end <- NA
  line_segments.df$y_end[mid_points+1] <- line_segments.df$y[mid_points+2]
  line_segments.df$x_end[mid_points+2] <- line_segments.df$x[mid_points+3]
  line_segments.df$y_end[mid_points+2] <- line_segments.df$y[mid_points+3]

  ## add segment from root node to its split node
  line_segments.df[1,] <- line_segments.df[2,]
  line_segments.df$y[1] <- line_segments.df$y[1]+node_spacing
  line_segments.df$x_end[1] <- line_segments.df$x[1]

  line_segments.df <- line_segments.df[stats::complete.cases(line_segments.df),]


  ## label the segments
  YES_NO.df <- line_segments.df
  YES_NO.df <- YES_NO.df[seq(2,nrow(YES_NO.df),2),c(5,6)]
  YES_NO.df$text <- "YES"
  YES_NO.df$text[seq(2,nrow(YES_NO.df),2)] <- "NO"






  result_object <- list(nodes.tbl = tibble::as_tibble(full_node.df),line_segments.tbl = tibble::as_tibble(line_segments.df),binary_tags.tbl = tibble::as_tibble(YES_NO.df),text_size = text_size)

  return(result_object)
}



## add line from top node to first split

