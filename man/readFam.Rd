% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/readFam.R
\name{readFam}
\alias{readFam}
\title{Read Familias \code{.fam} files}
\usage{
readFam(
  famfile,
  useDVI = NA,
  Xchrom = FALSE,
  prefixAdded = "added_",
  fallbackModel = c("equal", "proportional"),
  simplify1 = TRUE,
  deduplicate = TRUE,
  includeParams = FALSE,
  verbose = TRUE
)
}
\arguments{
\item{famfile}{Path (or URL) to a \code{.fam} file.}

\item{useDVI}{A logical, indicating if the DVI section of the \code{.fam} file
should be identified and parsed. If \code{NA} (the default), the DVI section is
included if it is present in the input file.}

\item{Xchrom}{A logical. If TRUE, the \code{chrom} attribute of all markers will
be set to "X". Default = FALSE.}

\item{prefixAdded}{A string used as prefix when adding missing parents.}

\item{fallbackModel}{Either "equal" or "proportional"; the mutation model to
be applied (with the same overall rate) when a specified model fails for
some reason. Default: "equal".}

\item{simplify1}{A logical indicating if the outer list layer should be
removed in the output if the file contains only a single pedigree.}

\item{deduplicate}{A logical, only relevant for DVI. If TRUE (default),
redundant copies of the reference pedigrees are removed.}

\item{includeParams}{A logical indicating if various parameters should be
read and returned in a separate list. See Value for details. Default:
FALSE.}

\item{verbose}{A logical. If TRUE, various information is written to the
screen during the parsing process.}
}
\value{
The output of \code{readFam()} depends on the contents of the input file,
and the argument \code{includeParams}. This is FALSE by default, giving the
following possible outcomes:
\itemize{
\item If the input file only contains a database, the output is a list of
information (name, alleles, frequencies, mutation model) about each locus.
This list can be used as \code{locusAttributes} in e.g. \code{\link[pedtools:marker_attach]{pedtools::setMarkers()}}.
\item If the input file describes pedigree data, the output is a list of \code{ped}
objects. If there is only one pedigree, and \code{simplify1 = TRUE}, the output
is a \code{ped} object.
\item If \code{useDVI = TRUE}, or \code{useDVI = NA} \emph{and} the file contains DVI data, then
the \verb{Reference Families} section of the file is parsed and converted to
\code{ped} objects. Each family generally describes multiple pedigrees, so the
output gets another layer in this case.
}

If \code{includeParams = TRUE}, the output is a list with elements \code{main} (the
main output, as described above) and \code{params}, a list with some or all of
the following entries:
\itemize{
\item \code{version}: The version of Familias
\item \code{dvi}: A logical indicating if a DVI section was read
\item \code{dbName}: The name of the database
\item \code{dbSize}: A named numeric vector containing the DatabaseSize reported for
each marker
\item \code{dropoutConsider}: A named logical vector indicating for each person if
dropouts should be considered
\item \code{dropoutValue}: A named numeric vector containing the dropout value for
each marker
\item \code{maf}: A named numeric vector containing the "Minor Allele Frequency"
given for each marker
\item \code{theta}: The \code{Theta/Kinship/Fst} value given for the marker database
}
}
\description{
Parses the content of a \code{.fam} file exported from Familias, and converts it
into suitable \code{ped} objects. This function does not depend on the \code{Familias}
R package.
}
\examples{
# Using example file "paternity.fam" included in the package
fam = system.file("extdata", "paternity.fam", package = "pedFamilias")

# Read and plot
peds = readFam(fam)
plotPedList(peds, hatched = typedMembers, marker = 1)

# Store parameters
x = readFam(fam, includeParams = TRUE)
x$params

stopifnot(identical(x$main, peds))

}
\references{
Egeland et al. (2000). \emph{Beyond traditional paternity and
identification cases. Selecting the most probable pedigree.} Forensic Sci
Int 110(1): 47-59.
}
\seealso{
\code{\link[=writeFam]{writeFam()}}.
}
