#############
# Functions #
#############

# labels
label.help <- function(label,id){
  shiny::HTML(paste0(label,actionLink(id,label=NULL,icon=icon('question-circle'))))
}

# Get neurons that have been selected
get_neurons<-function(input, db){
  skel.type = input$SkeletonType
  if(grepl("xample",input$Type)){
    cts = "PD2a1"
    skel.type = "FlyCircuit"
  }else if (is_lhn_type(input$Type)){
    if(sum(grepl("all",input$CT))>0){
      if(sum(grepl("all",input$AG))>0){
        AG = subset(db[,],pnt%in%input$PNT)[,"anatomy.group"]
      }else{
        AG = input$AG
      }
      CT = subset(db[,],anatomy.group%in%AG)[,"cell.type"]
    }else{
      CT = input$CT
    }
    if(sum(grepl("all",input$lhns))>0){
      lhn.cts = sort(unique(db[,"cell.type"]))
    }else{
      lhn.cts = input$lhns
    }
    cts = unique(c(lhn.cts,CT))
    cts = cts[cts%in%db[,"cell.type"]]
  }else if(input$Type=="MBON"){
    cts = input$MBON
  }else if (grepl("IN",input$Type)){
    cts = input$PN
  }else{
    cts = NULL
  }
  neurons = subset(db,skeleton.type%in%skel.type&cell.type%in%cts)
  neurons[,"colour"] = darjeeling(length(neurons)) # Assign darjeeling colours
  neurons
}

# Define a function for a frontal view of the brain
frontalView<-function(zoom=0.6){
  um=structure(c(1, 0, 0, 0, 0, -1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1), .Dim = c(4L, 4L))
  rgl.viewpoint(userMatrix=um,zoom=zoom)
}

# Plot a selection of pnts
plot_pnt <- function (pnts = "PD2") {
  plot.pnts = lhlite::primary.neurite.tracts[pnts]
  rgl::plot3d(plot.pnts, soma = T, lwd = 5, col = "grey20",skipRedraw = TRUE)
  pxyz = t(sapply(plot.pnts, function(x) nat::xyzmatrix(x)[nat::rootpoints(x),]))
  rownames(pxyz) = gsub(pattern = "LH|lh", "", names(plot.pnts))
  shift <- matrix(c(-3, 3, 0), nrow(pxyz), 3, byrow = TRUE)
  rgl::text3d(pxyz + shift, texts = rownames(pxyz))
}


# Wrapper function for dotprops.character to handle some checks/restrictions that are quite specific to shiny usage
dotprops_from_nrrd<-function(f, ...) {
  ni <- read.im3d(f, ReadData = F)
  
  imsize=prod(unlist(attr(ni,'datablock')[c("n","size")]))
  if(imsize > 150e6)
    stop("Nrrd image files must be <= 150 Mb uncompressed. Try downsampling to ~ 1 x 1 x 1 µm voxel size.")
  
  # read the image
  im=read.im3d(f, ReadByteAsRaw = TRUE)
  coords=ind2coord(im)
  if(nrow(coords) > 1e5)
    stop("Nrrd image contains > 100,000 non-zero voxels. Please use a skeletonised/binarised image as produced by http://fiji.sc/Skeletonize3D")
  
  dotprops(coords, ...)
}


# Work around to log into CATMAID via R Shiny
shiny_catmaid_login <- function (conn = NULL, ..., Cache = TRUE, Force = FALSE) 
{
  if (is.null(conn)) {
    if (!length(pairlist(...))) {
      conn = catmaid:::catmaid_last_connection()
    }
    if (is.null(conn)) 
      conn = shiny_catmaid_connection(...)
  }
  if (!Force) {
    if (!is.null(conn$authresponse)) 
      return(invisible(conn))
    cached_conn = catmaid:::catmaid_cached_connection(conn)
    if (!is.null(cached_conn)) 
      return(invisible(cached_conn))
  }
  if (isTRUE(conn$nologin)) {
    conn$authresponse = GET(url = conn$server)
    stop_for_status(conn$authresponse)
    res_cookies = cookies(conn$authresponse)
    csrf_row = grepl("csrf", res_cookies$name)
    if (any(csrf_row)) {
      token_value = res_cookies$value[csrf_row][1]
      conn$config = httr::add_headers(`X-CSRFToken` = token_value)
    }
    else warning("I can't seem to find a CSRF token.", "You will not be able to POST to this site!")
  }
  else {
    body <- if (is.null(conn$token)) 
      list(name = conn$username, pwd = conn$password)
    else NULL
    conn$authresponse = POST(url = paste0(conn$server, "/accounts/login"), 
                             body = body, config = conn$config)
    stop_for_status(conn$authresponse)
  }
  conn$cookies = unlist(cookies(conn$authresponse))
  conn$config = c(conn$config, set_cookies(conn$cookies))
  if (Cache) 
    catmaid:::catmaid_cache_connection(conn)
  invisible(conn)
}

# R Shiny work-around
shiny_catmaid_connection <-function (server, username = NULL, password = NULL, authname = NULL, 
                                     authpassword = NULL, token = NULL, authtype = NULL) 
{
  arglist = formals(fun = sys.function())
  argnames = names(arglist)
  conn = list(server = server, username = username, password = password, authname = authname, authpassword = authpassword, token = token, authtype = authtype)
  class(conn) = "catmaid_connection"
  if (is.null(conn$server) || !grepl("^http[s]{0,1}", conn$server)) 
    stop("Must provide a valid https server")
  if (is.null(conn$username) && is.null(conn$token)) {
    conn$nologin = TRUE
    return(invisible(conn))
  }
  if (is.null(conn$authname)) {
    conn$config = config()
  }
  else {
    if (is.null(conn$authtype)) 
      conn$authtype = "basic"
    conn$config = authenticate(conn$authname, conn$authpassword, 
                               type = conn$authtype)
  }
  if (!is.null(conn$token)) 
    conn$config = c(conn$config, add_headers(`X-Authorization` = paste("Token", 
                                                                       conn$token)))
  invisible(conn)
}

vfb_url <- function(neuron_name, style=c("dev", "old")) {
  style=match.arg(style, c("dev", "old"))
  vfb_id <- as.character(vfb_ids[vfb_ids$Name %in% neuron_name, 'vfbid'])
  if(style=='old'){
    paste0("http://www.virtualflybrain.org/site/tools/view_stack/3rdPartyStack.htm?json=FlyCircuit2012/", neuron_name, "/wlz_meta/tiledImageModelData.jso&type=THIRD_PARTY_STACK&tpbid=", vfb_id)
  } else {
    paste0("http://www.virtualflybrain.org/site/stacks/index.htm?add=", paste0(vfb_id, collapse=','), "&clear=true")
  }
}

vfb_link <- function(neuron_name) {
  url <- vfb_url(neuron_name)
  paste0("<a target='_blank' href='", url, "'>View in Virtual Fly Brain stack browser</a>")
}

is_lhn_type <- function(type){
  sum(sapply(c("^ON","^LN","^LHN"),grepl,type))>0
}

downloadskeletons <- function (nl, dir, format = "swc", subdir = NULL, INDICES = names(nl), files = NULL, Force = TRUE, ...){
  if (grepl("\\.zip", dir)) {
    zip_file = dir
    if (file.exists(zip_file)) {
      if (!Force){
        stop("Zip file: ", zip_file, "already exists")
      }else{
        unlink(zip_file)
      }
    }
    zip_dir = tools::file_path_as_absolute(dirname(zip_file))
    zip_file = file.path(zip_dir, basename(zip_file))
    dir <- file.path(tempfile("user_neurons"))
  } else {
    zip_file = NULL
  }
  if (!file.exists(dir)){
    dir.create(dir)
  }
  df = attr(nl, "df")
  ee = substitute(subdir)
  subdirs = NULL
  if (!is.null(ee) && !is.character(ee)) {
    if (!is.null(df))
      df = df[INDICES, ]
    subdirs = file.path(dir, eval(ee, df, parent.frame()))
    names(subdirs) = INDICES
  }
  ff = substitute(files)
  if (!is.null(ff)) {
    if (!is.character(ff))
      files = eval(ff, df, parent.frame())
    if (is.null(names(files)))
      names(files) = INDICES
  }
  written = structure(rep("", length(INDICES)+1), .Names = c(INDICES,"metadata"))
  for (nn in INDICES) {
    n = nl[[nn]]
    thisdir = dir
    if (is.null(subdirs)) {
      if (!is.null(subdir)) {
        propval = n[[subdir]]
        if (!is.null(propval))
          thisdir = file.path(dir, propval)
      }
    }
    else {
      thisdir = subdirs[nn]
    }
    if (!file.exists(thisdir))
      dir.create(thisdir, recursive = TRUE)
    written[nn] = nat::write.neuron(n, dir = thisdir, file = files[nn],
                                    format = format, Force = Force)
  }
  # Save metadata
  utils::write.csv(df,file = paste0(dir,"/neurons_metadata.csv"),row.names = FALSE)
  written["metadata"] = paste0(dir,"_metadata.csv")
  if (!is.null(zip_file)) {
    owd = setwd(dir)
    on.exit(setwd(owd))
    zip(zip_file, files = dir(dir, recursive = TRUE))
    unlink(dir, recursive = TRUE)
    written <- zip_file
  }
  invisible(written)
}

# downloadskeletons <- function(nl, dir, subdir = NULL, INDICES = names(nl), files = NULL){
#   fs <- c()
#   tmpdir <- tempdir()
#   setwd(tempdir())
#   for (i in INDICES) {
#     path <- paste0(tmpdir, i, ".swc")
#     fs <- c(fs, path)
#     utils::write.csv(nl[i][[1]]$d, path)
#   }
#   zip(zipfile=dir, files=fs)
# }
  
download_all_mophologies <- function(dir, ...){
  all.neurons = subset(lhlite::all.lh.neurons,skeleton.type%in%c("FlyCircuit", "DyeFill", "MCFO", "EM", "FijiTracing", "JeanneDyeFill"))
  most.lhins.pnt = subset(all.neurons,type=="PN")
  most.lhins.pnt[,"pnt"] = most.lhins.pnt[,"tract"]
  neurons = c(subset(all.neurons,type!="PN"),most.lhins.pnt)
  attr(neurons,"df") = neurons[,c("cell.type", "anatomy.group", "pnt", "tract","type", "skeleton.type", "coreLH", "id")]
  neurons[,"skeleton.type_pnt"] = paste0(neurons[,"skeleton.type"],"_",neurons[,"pnt"])
  downloadskeletons(neurons,dir = dir,subdir = skeleton.type_pnt,format="swc",files = paste0(cell.type,"_",id),Force = TRUE, ...)
}


resamplecatmaidneuron <- function (x, stepsize = 1, ...) {
  r = nat:::resample.neuron(x, stepsize = stepsize, ...)
  c = catmaid::connectors(x)
  c$treenode_id = nabor::knn(data = nat::xyzmatrix(r), query = nat::xyzmatrix(c), 
                             k = 1)$nn.idx
  r$connectors = c
  r
}






