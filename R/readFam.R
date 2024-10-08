#' Read Familias `.fam` files
#'
#' Parses the content of a `.fam` file exported from Familias, and converts it
#' into suitable `ped` objects. This function does not depend on the `Familias`
#' R package.
#'
#' @param famfile Path (or URL) to a `.fam` file.
#' @param useDVI A logical, indicating if the DVI section of the `.fam` file
#'   should be identified and parsed. If `NA` (the default), the DVI section is
#'   included if it is present in the input file.
#' @param Xchrom A logical. If TRUE, the `chrom` attribute of all markers will
#'   be set to "X". Default = FALSE.
#' @param prefixAdded A string used as prefix when adding missing parents.
#' @param fallbackModel Either "equal" or "proportional"; the mutation model to
#'   be applied (with the same overall rate) when a specified model fails for
#'   some reason. Default: "equal".
#' @param simplify1 A logical indicating if the outer list layer should be
#'   removed in the output if the file contains only a single pedigree.
#' @param deduplicate A logical, only relevant for DVI. If TRUE (default),
#'   redundant copies of the reference pedigrees are removed.
#' @param includeParams A logical indicating if various parameters should be
#'   read and returned in a separate list. See Value for details. Default:
#'   FALSE.
#' @param verbose A logical. If TRUE, various information is written to the
#'   screen during the parsing process.
#'
#' @return The output of `readFam()` depends on the contents of the input file,
#'   and the argument `includeParams`. This is FALSE by default, giving the
#'   following possible outcomes:
#'
#'   * If the input file only contains a database, the output is a list of
#'   information (name, alleles, frequencies, mutation model) about each locus.
#'   This list can be used as `locusAttributes` in e.g. [pedtools::setMarkers()].
#'
#'   * If the input file describes pedigree data, the output is a list of `ped`
#'   objects. If there is only one pedigree, and `simplify1 = TRUE`, the output
#'   is a `ped` object.
#'
#'   * If `useDVI = TRUE`, or `useDVI = NA` _and_ the file contains DVI data, then
#'   the `Reference Families` section of the file is parsed and converted to
#'   `ped` objects. Each family generally describes multiple pedigrees, so the
#'   output gets another layer in this case.
#'
#'   If `includeParams = TRUE`, the output is a list with elements `main` (the
#'   main output, as described above) and `params`, a list with some or all of
#'   the following entries:
#'
#'   * `version`: The version of Familias
#'   * `dvi`: A logical indicating if a DVI section was read
#'   * `dbName`: The name of the database
#'   * `dbSize`: A named numeric vector containing the DatabaseSize reported for
#'   each marker
#'   * `dropoutConsider`: A named logical vector indicating for each person if
#'   dropouts should be considered
#'   * `dropoutValue`: A named numeric vector containing the dropout value for
#'   each marker
#'   * `maf`: A named numeric vector containing the "Minor Allele Frequency"
#'   given for each marker
#'   * `theta`: The `Theta/Kinship/Fst` value given for the marker database
#'
#' @seealso [writeFam()].
#'
#' @references Egeland et al. (2000). _Beyond traditional paternity and
#'   identification cases. Selecting the most probable pedigree._ Forensic Sci
#'   Int 110(1): 47-59.
#'
#' @examples
#' # Using example file "paternity.fam" included in the package
#' fam = system.file("extdata", "paternity.fam", package = "pedFamilias")
#'
#' # Read and plot
#' peds = readFam(fam)
#' plotPedList(peds, hatched = typedMembers, marker = 1)
#'
#' # Store parameters
#' x = readFam(fam, includeParams = TRUE)
#' x$params
#'
#' stopifnot(identical(x$main, peds))
#'
#' @importFrom pedmut mutationMatrix
#' @export
readFam = function(famfile, useDVI = NA, Xchrom = FALSE, prefixAdded = "added_",
                   fallbackModel = c("equal", "proportional"), simplify1 = TRUE,
                   deduplicate = TRUE, includeParams = FALSE, verbose = TRUE) {

  if(!endsWith(famfile, ".fam"))
    stop2("Input file must end with '.fam': ", famfile)

  if(any(startsWith(famfile, c("http", "ftp", "www"))) && verbose)
    cat("Reading from URL:", famfile, "\n")
  else if(!file.exists(famfile))
    stop2("File not found: ", famfile)

  # Read entire file
  raw = readLines(famfile)
  x = gsub("\\\"", "", raw)

  # Utility function for checking integer values
  getInt = function(line, txt, value = x[line], max = Inf) {
    if(is.na(j <- suppressWarnings(as.integer(value))) || j > max)
      stop2(sprintf('Expected line %d to be %s, but found: "%s"',
                   line, txt, value))
    j
  }

  # Initialise storage for extra info, if indicated
  params = if(includeParams) list() else NULL

  # Read and print Familias version
  version = x[3]
  params$version = version
  if(verbose)
    cat("Familias version:", version, "\n")

  if(is.na(useDVI))
    useDVI = "[DVI]" %in% x
  else if(useDVI && !"[DVI]" %in% x)
    stop2("No DVI section found in input file")

  if(verbose)
    cat("Read DVI:", if(useDVI) "Yes\n" else "No\n")

  params$dvi = useDVI

  ### Individuals and genotypes

  # Number of individuals
  nid.line = if(x[4] != "") 4 else 5
  nid = getInt(nid.line, "number of individuals") # all excluding "extras"
  if(verbose)
    cat("\nNumber of individuals (excluding 'extras'):", nid, "\n")

  # Initialise id & sex
  id = character(nid)
  sex = integer(nid)

  # Initialise list holding genotypes (as allele indices)
  datalist = vector("list", nid)

  # Read data for each individual
  id.line = nid.line + 1
  for(i in seq_len(nid)) {
    id[i] = x[id.line]

    if(includeParams) {
      dr = grepl("(Consider dropouts)", x[id.line + 2])
      names(dr) = id[i]
      params$dropoutConsider = c(params$dropoutConsider, dr)
    }

    sex[i] = ifelse(x[id.line + 4] == "#TRUE#", 1, 2)

    nmi = getInt(id.line + 5, sprintf('number of genotypes for "%s"', id[i]))
    if(verbose)
      cat(sprintf("  Individual '%s': Genotypes for %d markers read\n", id[i], nmi))

    a1.lines = seq(id.line + 6, by = 3, length = nmi)
    a1.idx = as.integer(x[a1.lines]) + 1
    a2.idx = as.integer(x[a1.lines + 1]) + 1
    mark.idx = as.integer(x[a1.lines + 2]) + 1
    datalist[[i]] = list(id = id[i], a1.idx = a1.idx,
                         a2.idx = a2.idx, mark.idx = mark.idx)

    id.line = id.line + 6 + 3*nmi
  }

  ### Fixed relations

  # Storage for twins
  twins = list()

  kr.line = id.line
  if(x[kr.line] != "Known relations")
    stop2(sprintf('Expected line %d to be "Known relations", but found: "%s"', id.line, x[id.line]))

  # Add extras to id & sex
  nFem = as.integer(x[kr.line + 1])
  nMal = as.integer(x[kr.line + 2])
  id = c(id, sprintf("extra_%d", seq_len(nFem + nMal)))
  sex = c(sex, rep.int(2:1, c(nFem, nMal)))

  # Initialise fidx, midx
  fidx = midx = integer(length(id))

  # Add fixed relations
  nRel = as.integer(x[kr.line + 3])
  rel.line = kr.line + 4
  for(i in seq_len(nRel)) {
    par.idx = as.integer(x[rel.line]) + 1
    child.idx = as.integer(x[rel.line+1]) + 1
    if(sex[par.idx] == 1)
      fidx[child.idx] = par.idx
    else
      midx[child.idx] = par.idx

    # Goto next relation
    rel.line = rel.line + 2
  }

  # Initialise list of final pedigrees
  nPed = getInt(rel.line, "number of pedigrees")
  if(verbose)
    cat("\nNumber of pedigrees:", nPed, "\n")

  # If no more pedigree info, finish pedigree part
  if(nPed == 0) {
    pedigrees = asFamiliasPedigree(id, fidx, midx, sex)
  }
  ped.line = rel.line + 1

  ### Additional relationships, unique to each ped
  if(nPed > 0) {
    pedigrees = vector("list", nPed)

    # Process each pedigree
    for(i in seq_len(nPed)) {
      ped.idx = as.integer(x[ped.line]) + 1
      ped.name = x[ped.line + 1]

      # Add extras in the i'th pedigree
      nFem.i = as.integer(x[ped.line + 2])
      nMal.i = as.integer(x[ped.line + 3])
      id.i = c(id, sprintf("extra_ped%d_%d", ped.idx, seq_len(nFem.i + nMal.i)))
      sex.i = c(sex, rep.int(2:1, c(nFem.i, nMal.i)))
      fidx.i = c(fidx, integer(nFem.i + nMal.i))
      midx.i = c(midx, integer(nFem.i + nMal.i))

      # Print summary
      if(verbose)
        cat(sprintf("  Pedigree '%s' (%d extra females, %d extra males)\n", ped.name, nFem.i, nMal.i))

      # Add fixed relations
      nRel.i = as.integer(x[ped.line + 4])
      rel.line = ped.line + 5
      for(j in seq_len(nRel.i)) {
        par.idx = as.integer(x[rel.line]) + 1
        child.idx = as.integer(x[rel.line+1]) + 1
        if(is.na(par.idx)) {
          if(grepl("Direct", x[rel.line])) {
            par.idx = as.integer(substring(x[rel.line], 1, 1)) + 1
            twins = c(twins, list(par.idx, child.idx))
            if(verbose) cat("  Twins:", toString(id.i[c(par.idx, child.idx)]), "\n")
            stop2("File contains twins - this is not supported yet")
          }
        }
        if(sex.i[par.idx] == 1)
          fidx.i[child.idx] = par.idx
        else
          midx.i[child.idx] = par.idx

        rel.line = rel.line + 2
      }


      # Convert to familiaspedigree and insert in list
      pedigrees[[ped.idx]] = asFamiliasPedigree(id.i, fidx.i, midx.i, sex.i)
      names(pedigrees)[ped.idx] = ped.name

      # Goto next ped
      ped.line = rel.line
    }
  }

  has.probs = startsWith(x[ped.line], "#TRUE#")
  if(has.probs)
    stop("\nThis file includes precomputed probabilities; this is not supported yet.")

  ### Database ###

  fallbackModel = match.arg(fallbackModel)

  # Theta?
  patt = "(?<=Theta/Kinship/Fst: )[\\.\\d]+"
  theta = safeNum(regmatches(x[ped.line], regexpr(patt, x[ped.line], perl = TRUE)))
  if(includeParams)
    params$theta = theta
  else if(length(theta) && !is.na(theta) && theta > 0)
    warning("Nonzero theta correction detected: theta = ", theta, call. = FALSE)

  db.line = ped.line + 1
  nLoc = getInt(db.line, "number of loci")

  has.info = x[db.line + 1] == "#TRUE#"
  if(verbose) {
    if(has.info)
      cat("\nDatabase:", x[db.line + 2], "\n")
    else
      cat("\n")
  }

  if(includeParams)
    params$dbName = if(has.info) x[db.line + 2] else ""

  if(verbose)
    cat("Number of loci:", nLoc, "\n")

  loci = vector("list", nLoc)
  loc.line = db.line + 2 + has.info

  # Loop over database loci
  for(i in seq_len(nLoc)) {
    loc.name = x[loc.line]
    mutrate.fem = as.numeric(x[loc.line + 1])
    mutrate.mal = as.numeric(x[loc.line + 2])
    model.idx.fem = getInt(loc.line + 3, "an integer code (0-4) for the female mutation model", max = 4)
    model.idx.mal = getInt(loc.line + 4, "an integer code (0-4) for the male mutation model", max = 4)

    nAll.with.silent = as.integer(x[loc.line + 5]) # includes silent allele

    range.fem = as.numeric(x[loc.line + 6])
    range.mal = as.numeric(x[loc.line + 7])

    mutrate2.fem = as.numeric(x[loc.line + 8])
    mutrate2.mal = as.numeric(x[loc.line + 9])

    has.silent = x[loc.line + 10] == "#TRUE#"
    if(has.silent)
      stop2("Locus ", loc.name, " has silent frequencies: this is not implemented yet")
    silent.freq = as.numeric(x[loc.line + 11])

    # Info line, e.g. "17\t(DatabaseSize = 600 , Dropout probability = 0 , Minor allele frequency = 0 )"
    mInfo = unlist(strsplit(x[loc.line + 12], "\t"))

    # First part: Number of alleles except the silent
    nAll = getInt(loc.line + 12, value = mInfo[[1]],
                  paste("number of alleles for marker", loc.name))

    # Second part I: Database size
    if(includeParams) {
      patt1 = "(?<=DatabaseSize = )\\d+"
      dbsize = safeNum(regmatches(mInfo[[2]], regexpr(patt1, mInfo[[2]], perl = TRUE)))
      if(length(dbsize))
        params$dbSize = c(params$dbSize, setnames(dbsize, loc.name))
    }

    # Second part II: Dropout value per marker
    if(includeParams) {
      patt2 = "(?<=Dropout probability = )[\\.\\d]+"
      drVal = safeNum(regmatches(mInfo[[2]], regexpr(patt2, mInfo[[2]], perl = TRUE)))
      if(length(drVal))
        params$dropoutValue = c(params$dropoutValue, setnames(drVal, loc.name))
    }

    # Second part III: Minor allele frequency
    if(includeParams) {
      patt3 = "(?<=Minor allele frequency = )[\\.\\d]+"
      thismaf = safeNum(regmatches(mInfo[[2]], regexpr(patt3, mInfo[[2]], perl = TRUE)))
      if(length(thismaf))
        params$maf = c(params$maf, setnames(thismaf, loc.name))
    }

    # Read alleles and freqs
    als.lines = seq(loc.line + 13, by = 2, length.out = nAll)
    als = x[als.lines]
    frqs = as.numeric(x[als.lines + 1])

    if("0" %in% als) {
      warning(sprintf("Database error, locus %s: Illegal allele '0'. Changed to 'z'.", loc.name), call. = FALSE)
      als[als == "0"] = "z"
    }

    # Check for illegal alleles, including "Rest allele", with stepwise models
    if(model.idx.mal > 1 || model.idx.fem > 1) {
      change = FALSE
      alsNum = safeNum(als)
      if(any(is.na(alsNum))) {
        change = TRUE
        warning(sprintf("Database error, locus %s: Non-numerical allele '%s' incompatible with stepwise model. Changed to '%s' model.",
                        loc.name, als[is.na(alsNum)][1], fallbackModel), call. = FALSE)
      }
      else if(any(alsNum < 1)) {
        change = TRUE
        warning(sprintf("Database error, locus %s: Allele '%s' incompatible with stepwise model. Changed to '%s' model.",
                        loc.name, als[alsNum < 1][1], fallbackModel), call. = FALSE)
      }
      else {
        badMicro = round(alsNum, 1) != alsNum
        if(any(badMicro)) {
          change = TRUE
          warning(sprintf("Database error, locus %s: Illegal microvariant '%s'. Changed to '%s' mutation model.",
                          loc.name, als[badMicro][1], fallbackModel), call. = FALSE)
        }
      }
      if(change) {
        model.idx.mal = model.idx.fem = switch(fallbackModel, equal = 0, proportional = 1)
      }
    }

    # After checks, associate alleles with freqs
    names(frqs) = als

    # Mutation models
    models = c("equal", "proportional", "stepwise", "stepwise", "stepwise")
    names(models) = c("equal", "prop", "step-unstationary", "step-stationary", "step-ext")

    maleMod = models[model.idx.mal + 1]
    femaleMod = models[model.idx.fem + 1]

    maleMutMat = mutationMatrix(model = maleMod, alleles = als, afreq = frqs,
                                rate = mutrate.mal, rate2 = mutrate2.mal, range = range.mal)
    femaleMutMat = mutationMatrix(model = femaleMod, alleles = als, afreq = frqs,
                                  rate = mutrate.fem, rate2 = mutrate2.fem, range = range.fem)

    if(names(maleMod) == "step-stationary") {
      maleMutMat = tryCatch(pedmut::stabilize(maleMutMat, method = "PM"),
        error = function(e) {
          warning(sprintf("Database error, locus %s: Cannot stabilize mutation matrix. Changed to '%s' model.",
                          loc.name, fallbackModel), call. = FALSE)
          mutationMatrix(model = fallbackModel, alleles = als, afreq = frqs, rate = mutrate.mal)
        })
      if(pedmut::getParams(maleMutMat, "model") == fallbackModel)
         maleMod = models[models == fallbackModel]
    }

    if(names(femaleMod) == "step-stationary") {
      femaleMutMat = tryCatch(pedmut::stabilize(femaleMutMat, method = "PM"),
        error = function(e) mutationMatrix(model = fallbackModel, alleles = als, afreq = frqs, rate = mutrate.fem))
      if(pedmut::getParams(femaleMutMat, "model") == fallbackModel)
         femaleMod = models[models == fallbackModel]
    }

    # Print locus summary
    if(verbose) {
      if(identical(maleMutMat, femaleMutMat)) {
        mut_txt = sprintf("unisex mut model = %s, rate = %.2g", names(maleMod), mutrate.mal)
        if(maleMod == "stepwise")
          mut_txt = paste0(mut_txt, sprintf(", range = %.2g, rate2 = %.2g", range.mal, mutrate2.mal))
      }
      else {
        mod = if(names(maleMod) == names(femaleMod)) names(maleMod) else paste(names(maleMod), names(femaleMod), sep = "/")
        rate = if(mutrate.mal == mutrate.fem) sprintf("%.2g", mutrate.mal) else sprintf("%.2g/%.2g", mutrate.mal, mutrate.fem)
        mut_txt = sprintf("mut model (M/F) = %s, rate = %s", mod, rate)
        if(maleMod == "stepwise" && femaleMod == "stepwise") {
          range = if(range.mal == range.fem) sprintf("%.2g", range.mal) else sprintf("%.2g/%.2g", range.mal, range.fem)
          rate2 = if(mutrate2.mal == mutrate2.fem) sprintf("%.2g", mutrate2.mal) else sprintf("%.2g/%.2g", mutrate2.mal, mutrate2.fem)
          mut_txt = paste0(mut_txt, sprintf(", range = %s, rate2 = %s", range, rate2))
        }
        else if(maleMod == "stepwise")
          mut_txt = paste0(mut_txt, sprintf(", range = %.2g, rate2 = %.2g", range.mal, mutrate2.mal))
        else if(femaleMod == "stepwise")
          mut_txt = paste0(mut_txt, sprintf(", range = %.2g, rate2 = %.2g", range.fem, mutrate2.fem))
      }
      cat(sprintf("  %s: %d alleles, %s\n", loc.name, length(frqs), mut_txt))
    }

    # Collect locus info
    loci[[i]] = list(locusname = loc.name, alleles = frqs,
                     femaleMutationType = femaleMod,
                     femaleMutationMatrix = femaleMutMat,
                     maleMutationType = maleMod,
                     maleMutationMatrix = maleMutMat)

    # Goto next locus
    loc.line = loc.line + 13 + 2*nAll
  }

  ###########
  ### DVI ###
  ###########

  if(useDVI) {
    if(verbose)
      cat("\n*** Reading DVI section ***\n")
    dvi.start = match("[DVI]", raw)
    if(is.na(dvi.start))
      stop2("Expected keyword '[DVI]' not found")
    dvi.lines = raw[dvi.start:length(raw)]
    dvi.families = readDVI(dvi.lines, deduplicate = deduplicate, verbose = verbose)

    if(verbose)
      cat("*** Finished DVI section ***\n\n")

    if(verbose)
      cat("Converting to `ped` format\n")
    res = lapply(dvi.families, function(fam) {
      Familias2ped(familiasped = fam$pedigrees, datamatrix = fam$datamatrix,
                   loci = loci, matchLoci = TRUE, prefixAdded = prefixAdded)
    })

    # Set all chrom attributes to X if indicated
    if(Xchrom) {
      if(verbose) cat("Changing all chromosome attributes to `X`\n")
      chrom(res, seq_along(loci)) = "X"
    }

    if(includeParams)
      res = list(main = res, params = params)

    if(verbose)
      cat("\n")

    return(res)
  }

  ##################
  ### If not DVI ###
  ##################

  ### datamatrix ###
  has.data = nid > 0 && any(lengths(sapply(datalist, '[[', "mark.idx")))
  if(!has.data) {
    datamatrix = NULL
  }
  else {
    loc.names = vapply(loci, function(ll) ll$locusname, FUN.VALUE = "")

    # Organise observed alleles in two index matrices
    dm.a1.idx = dm.a2.idx = matrix(NA, nrow = nid, ncol = nLoc,
                                   dimnames = list(id[seq_len(nid)], loc.names))
    for(i in seq_len(nid)) {
      g = datalist[[i]]
      dm.a1.idx[i, g$mark.idx] = g$a1.idx
      dm.a2.idx[i, g$mark.idx] = g$a2.idx
    }

    # Initalise data matrix
    dmn = list(id[seq_len(nid)], paste(rep(loc.names, each = 2), 1:2, sep = "."))
    datamatrix = matrix(NA_character_, nrow = nid, ncol = 2*nLoc, dimnames = dmn)

    # Fill in observed alleles
    for(i in seq_len(nLoc)) {
      als.i = names(loci[[i]]$alleles)
      datamatrix[, 2*i - 1] = als.i[dm.a1.idx[, i]]
      datamatrix[, 2*i]     = als.i[dm.a2.idx[, i]]
    }
  }

  # Return
  if(!is.null(pedigrees)) {
    if(verbose)
      cat("\nConverting to `ped` format\n")
    res = Familias2ped(familiasped = pedigrees, datamatrix = datamatrix, loci = loci,
                       prefixAdded = prefixAdded)

    # Set all chrom attributes to X if indicated
    if(Xchrom) {
      if(verbose) cat("Changing all chromosome attributes to `X`\n")
      chrom(res, seq_along(loci)) = "X"
    }

    # Simplify output if single pedigree
    if(simplify1 && length(res) == 1)
      res = res[[1]]
  }
  else {
    if(verbose)
      cat("\nReturning database only\n")
    res = readFamiliasLoci(loci = loci)
  }

  if(includeParams)
    res = list(main = res, params = params)

  if(verbose) cat("\n")

  res
}




# Create a FamiliasPedigree from scratch (without loading Familias package)
asFamiliasPedigree = function(id, findex, mindex, sex) {
  if(length(id) == 0)
    return(NULL)

  if(is.numeric(sex))
    sex = ifelse(sex == 1, "male", "female")

  x = list(id = id, findex = findex, mindex = mindex, sex = sex)
  class(x) = "FamiliasPedigree"

  x
}

#########################################
### Utilities for parsing DVI section ###
#########################################

readDVI = function(rawlines, deduplicate = TRUE, verbose = TRUE) {
  r = rawlines
  if(r[1] != "[DVI]")
    stop2("Expected the first line of DVI part to be '[DVI]': ", r[1])

  ### Parse raw lines into nested list named `dvi`
  dvi = list()
  ivec = character()

  # number of brackets on each line
  brackets = as.integer(regexpr("[^[]", r)) - 1

  # pre-split lines
  splits = strsplit(r, "= ")

  # Populate `dvi` list
  for(i in seq_along(r)) {
    line = r[i]
    if(line == "")
      next
    br = brackets[i]

    if(br == 0) {
      dvi[[ivec]] = c(dvi[[ivec]], list(splits[[i]]))
    }
    else {
      name = gsub("[][]", "", line)
      ivec = c(ivec[seq_len(br - 1)], name)
      dvi[[ivec]] = list()
    }

  }

  # Initialise output list
  res = list()

  # Unidentified persons, if any
  un = parseUnidentified(dvi$DVI$`Unidentified persons`, verbose = verbose)
  if(!is.null(un))
    res$`Unidentified persons` = un

  # Reference families
  refs_raw = dvi$DVI$`Reference Families`
  refs = refs_raw[-1] # remove 'nFamilies'

  stopifnot((nFam <- length(refs)) == as.integer(refs_raw[[c(1,2)]]))
  if(verbose)
    cat("\nReference families:", nFam, "\n")

  names(refs) = sapply(refs, function(fam) fam[[1]][2])
  refs = lapply(refs, function(rf) parseFamily(rf, deduplicate = deduplicate, verbose = verbose))

  # Return
  c(res, refs)
}

parseUnidentified = function(x, verbose = TRUE) {
  if(length(x) == 0)
    return(NULL)

  nPers = x[[c(1,2)]]
  if(verbose)
    cat("Unidentified persons:", nPers, "\n")

  if(nPers == "0")
    return(NULL)

  x = x[-1]

  ### id and sex
  id = sapply(x, function(p) getValue(p[[1]], iftag = "Name", NA))
  sex = sapply(x, function(p) getValue(p[[2]], iftag = "Gender", 0))
  sex[sex == "Male"] = 1
  sex[sex == "Female"] = 2
  s = asFamiliasPedigree(as.character(id), 0, 0, as.integer(sex))

  if(verbose)
    for(nm in id) cat(" ", nm, "\n")

  ### datamatrix
  vecs = lapply(x, function(p) dnaData2vec(p$`DNA data`))

  # Remove NULLs
  vecs = vecs[!sapply(vecs, is.null)]

  # All column names
  allnames = unique(unlist(lapply(vecs, names)))

  # Ensure same order in each vector, and fill in NA's
  vecs_ordered = lapply(vecs, function(v) structure(v[allnames], names = allnames))

  # Bind to matrix
  datamatrix = do.call(rbind, vecs_ordered)
  rownames(datamatrix) = id[rownames(datamatrix)]

  ### return
  list(pedigrees = s, datamatrix = datamatrix)
}

# Convert a "DVI Family" into a list of `datamatrix` and `pedigrees`
parseFamily = function(x, deduplicate, verbose = TRUE) {

  famname = x[[c(1,2)]]
  nPers = as.integer(x$Persons[[c(1,2)]])
  nPeds = as.integer(x$Pedigrees[[c(1,2)]])

  if(verbose)
    cat(sprintf("  %s (%d persons, %d pedigrees)\n", famname, nPers, nPeds))

  ### Persons
  persons_list = x$Persons[-1]

  id = sapply(persons_list, function(p) getValue(p[[1]], iftag = "Name", NA))
  sex = sapply(persons_list, function(p) getValue(p[[2]], iftag = "Gender", 0))

  sex[sex == "Male"] = 1
  sex[sex == "Female"] = 2
  sex = as.integer(sex)

  ### pedigrees
  ped_list = x$Pedigrees[-1] # remove "nPedigrees"
  names(ped_list) = sapply(ped_list, function(pd) getValue(pd[[1]], iftag = "Name", NA))

  # Check for duplicatation
  dedup = deduplicate && length(ped_list) == 2 && identical(ped_list[[1]][-1], ped_list[[2]][-1])

  pedigrees = lapply(ped_list, function(pd) {
    pednm = pd[[1]][2]
    skipthis = dedup && pednm == "Reference pedigree"

    if(verbose)
      cat(sprintf("    %s%s\n", pednm, if(skipthis) " [REMOVED]" else ""))

    if(skipthis)
      return(NULL)

    this.id = as.character(id)
    this.sex = sex

    tags = sapply(pd, '[', 1)
    vals = sapply(pd, '[', 2)

    # Data frame of parent-child pairs
    parent.tags = which(tags == "Parent")
    po = data.frame(parent = vals[parent.tags], child = vals[parent.tags + 1],
                    stringsAsFactors = FALSE)

    # Add extra individuals if needed (e.g. "Missing person")
    extras <- setdiff(c(po$parent, po$child), id)
    if(length(extras)) {
      this.id = c(this.id, extras)
      this.sex = c(this.sex, rep(0L, length(extras)))
    }

    names(this.sex) = this.id
    parent.sex = this.sex[po$parent]

    # Try to fix parents with undecided sex
    if(any(parent.sex == 0)) {
      par.nosex = unique(po$parent[parent.sex == 0])
      for(p in par.nosex) {
        chi = po$child[po$parent == p] # children of him/her
        spou = unique(setdiff(po$parent[po$child %in% chi], p))
        if(all(this.sex[spou] == 1))
          this.sex[p] = 2
        else if(all(this.sex[spou] == 2))
          this.sex[p] = 1
        else
          stop2("Cannot decide sex of this parent: ", p)
      }

      # Now try again
      parent.sex = this.sex[po$parent]
    }

    parent.idx = match(po$parent, this.id)
    child.idx = match(po$child, this.id)

    # Create and populate fidx and midx
    this.fidx = this.midx = integer(length(this.id))
    this.fidx[child.idx[parent.sex == 1]] = parent.idx[parent.sex == 1]
    this.midx[child.idx[parent.sex == 2]] = parent.idx[parent.sex == 2]

    # Return
    asFamiliasPedigree(this.id, this.fidx, this.midx, this.sex)
  })

  # If deduplication, remove redundant layer
  if(dedup) {
    keepthis = which(names(pedigrees) != "Reference pedigree")
    pedigrees = pedigrees[[keepthis]]
  }

  ### datamatrix
  vecs = lapply(persons_list, function(p) dnaData2vec(p$`DNA data`))

  # Remove NULLs
  vecs = vecs[!sapply(vecs, is.null)]

  # All column names
  allnames = unique(unlist(lapply(vecs, names)))

  # Ensure same order in each vector, and fill in NA's
  vecs_ordered = lapply(vecs, function(v) structure(v[allnames], names = allnames))

  # Bind to matrix
  datamatrix = do.call(rbind, vecs_ordered)
  rownames(datamatrix) = id[rownames(datamatrix)]

  ### return
  list(pedigrees = pedigrees, datamatrix = datamatrix)
}


# DNA data for single person --> named vector
dnaData2vec = function(x) {
  dat = do.call(rbind, x)
  val = dat[, 2]

  idx = which(dat[,1] == "SystemName")
  nLoc = length(idx)
  if(nLoc == 0)
    return()

  res = character(2 * nLoc)
  res[2*(1:nLoc) - 1] = val[idx + 1]
  res[2*(1:nLoc)] = val[idx + 2]
  names(res) = paste(rep(val[idx], each = 2), 1:2, sep = ".")
  res
}

getValue = function(x, iftag, default) {
  if(x[1] == iftag) x[2] else default
}

# Safe version of as.numeric
safeNum = function(x) {
  suppressWarnings(as.numeric(x))
}
