#' Convert `Familias` R objects to `ped`
#'
#' Convert pedigrees and marker data from the `Familias` R package into the
#' `ped` format used by the `pedsuite`.
#'
#' The definition of a *pedigree* in Familias is more liberal than that
#' implemented in the `pedsuite`, which requires that each `ped` object is a
#' connected pedigree, and that each member has either 0 or 2 parents. The
#' conversion function `Familias2ped` takes care of all potential differences.
#' Specifically, it converts each `FamiliasPedigree` object into a list of
#' connected `ped` components, and adds missing parents when needed.
#'
#' @param familiasped A `FamiliasPedigree` object or a list of such.
#' @param datamatrix A data frame with two columns per marker (one for each
#'   allele) and one row per individual.
#' @param loci A `FamiliasLocus` object or a list of such.
#' @param matchLoci A logical, by default FALSE. If TRUE, the column names of
#'   `datamatrix` are matched against `names(loci)`, or, if these are missing,
#'   against the `name` entries of `loci`. The column names of `datamatrix` are
#'   assumed to come in pairs with suffixes ".1" and ".2", e.g. "TH01.1",
#'   "TH01.2", etc. If FALSE, the `loci` are assumed to be in correct order, and
#'   no matching on marker name is done.
#' @param prefixAdded A string used as prefix when adding missing parents.
#'
#' @return A `ped` object, or a list of such.
#'
#' @seealso [readFam()].
#'
#' @references Familias is freely available from <https://familias.name>.
#' @examples
#'
#' famPed = list(id = c('mother', 'daughter', 'AF'),
#'               findex = c(0, 3, 0),
#'               mindex = c(0, 1, 0),
#'               sex = c('female', 'female', 'male'))
#' class(famPed) = "FamiliasPedigree"
#'
#' datamatrix = data.frame(
#'   M1.1 = c(NA, 8, NA),
#'   M1.2 = c(NA, 9.3, NA),
#'   row.names = famPed$id)
#'
#' famLoc = list(locusname = "M1",
#'               alleles = c("8" = 0.2, "9" = 0.5, "9.3" = 0.3))
#' class(famLoc) = "FamiliasLocus"
#'
#' Familias2ped(famPed, datamatrix, loci = famLoc, matchLoci = TRUE)
#'
#' @export
Familias2ped = function(familiasped, datamatrix, loci, matchLoci = FALSE,
                        prefixAdded = "added_") {

  ### If first argument is a list of FamiliasPedigrees, convert one at a time.
  if (is.list(familiasped) && inherits(familiasped[[1]], "FamiliasPedigree")) {
      res = lapply(familiasped, function(p)
        Familias2ped(p, datamatrix = datamatrix, loci = loci, matchLoci = matchLoci, prefixAdded = prefixAdded))
      return(res)
  }
  else if(!inherits(familiasped, "FamiliasPedigree"))
    stop2("The first argument must be a `FamiliasPedigree` or a list of such")


  ### Part 1: pedigree
  id = familiasped$id
  findex = familiasped$findex
  mindex = familiasped$mindex

  p = data.frame(id = id, fid = 0, mid = 0, sex = 1, stringsAsFactors = FALSE)
  p$fid[findex > 0] = id[findex]
  p$mid[mindex > 0] = id[mindex]
  p$sex[tolower(familiasped$sex) == "female"] = 2

  fatherMissing = which(p$fid == 0 & p$mid != 0)
  motherMissing = which(p$fid != 0 & p$mid == 0)

  nFath = length(fatherMissing)
  nMoth = length(motherMissing)

  newFathers = paste0(prefixAdded, seq(1, length.out = nFath))
  newMothers = paste0(prefixAdded, seq(nFath + 1, length.out = nMoth))

  # add new fathers
  if (nFath > 0) {
    p = rbind(p, data.frame(id = newFathers, fid = 0, mid = 0, sex = 1))
    p[fatherMissing, "fid"] = newFathers
  }

  # add new mothers
  if (nMoth > 0) {
    p = rbind(p, data.frame(id = newMothers, fid = 0, mid = 0, sex = 2))
    p[motherMissing, "mid"] = newMothers
  }

  ### Part2: datamatrix

  if (!is.null(datamatrix)) {

    # Matrices are safer to manipulate
    datamatrix = as.matrix(datamatrix)

    NC = ncol(datamatrix)

    if(matchLoci && is.null(colnames(datamatrix)))
        stop2("`datamatrix` must have column names")
    if(!matchLoci && length(loci) > 0) {

      if(NC != 2 * length(loci))
        stop2("When `matchLoci is FALSE, the number of columns in `datamatrix` must be `2*length(loci)`")
      colnames(datamatrix) = rep(NA, NC) # needed to avoid wrong names in cbind later!
    }

    # add rows for missing individuals
    miss = setdiff(familiasped$id, rownames(datamatrix))
    if(length(miss)) {
      empty = matrix("0", nrow = length(miss), ncol = NC,
                     dimnames = list(miss, NULL))
      datamatrix = rbind(datamatrix, empty)
    }

    # sort relevant part of datamatrix
    id_idx = match(familiasped$id, rownames(datamatrix))
    if (anyNA(id_idx))
      stop2("ID label not found among the datamatrix rownames: ",
            setdiff(familiasped$id, rownames(datamatrix)))
    datamatrix = datamatrix[id_idx, , drop = FALSE]

    # replace NA with 0
    datamatrix[is.na(datamatrix)] = "0"

    # add empty rows corresponding to new parents
    addedParents = matrix("0", nrow = nFath + nMoth, ncol = NC)
    allelematrix = rbind(datamatrix, addedParents)

    p = cbind(p, allelematrix, stringsAsFactors = FALSE)
  }

  ### Part 3: marker attributes
  locusAttributes = readFamiliasLoci(loci)

  ### Create ped object
  as.ped(p, locusAttributes = locusAttributes)
}



#' @rdname Familias2ped
#' @importFrom pedmut mutationMatrix mutationModel validateMutationModel
#' @export
readFamiliasLoci = function(loci) {
  if (is.null(loci))
    return(NULL)
  if (inherits(loci, "FamiliasLocus"))
    loci = list(loci)

  lapply(loci, function(a) {
    als = names(a$alleles)
    afreq = as.numeric(a$alleles)

    malemut = a$maleMutationMatrix
    femalemut = a$femaleMutationMatrix

    if (all(diag(malemut) == 1))
      malemut = NULL
    else if(!inherits(malemut, "mutationMatrix"))  # not sure when this is needed!
      malemut = mutationMatrix("custom", matrix = malemut, afreq = afreq)

    if (all(diag(femalemut) == 1))
      femalemut = NULL
    else if(!inherits(femalemut, "mutationMatrix"))
      femalemut = mutationMatrix("custom", matrix = femalemut, afreq = afreq)

    if (is.null(malemut) && is.null(femalemut))
      mutmod = NULL
    else {
      mutmod = mutationModel(list(female = femalemut, male = malemut))
    }

    list(name = a$locusname, alleles = als, afreq = afreq, mutmod = mutmod)
  })
}
