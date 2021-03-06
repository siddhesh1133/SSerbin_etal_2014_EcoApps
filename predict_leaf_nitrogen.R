####################################################################################################
#
#  
#   Predict foliar N using SSerbin et al (2014) PLSR models applied to dried and ground leaf spectra 
#   collected at NEON sites
#
#   Spectra and trait data source:
#   https://ecosis.org/package/dried-leaf-spectra-to-estimate-foliar-functional-traits-over-neon-domains-in-eastern-united-states
#
#    Notes:
#    * Provided as a basic example of how to apply the model to new spectra observations
#    * The author notes the code is not the most elegant or clean, but is functional 
#    * Questions, comments, or concerns can be sent to sserbin@bnl.gov
#    * Code is provided under GNU General Public License v3.0 
#
#
#    --- Last updated:  11.12.2019 By Shawn P. Serbin <sserbin@bnl.gov>
####################################################################################################


#---------------- Close all devices and delete all variables. -------------------------------------#
rm(list=ls(all=TRUE))   # clear workspace
graphics.off()          # close any open graphics
closeAllConnections()   # close any open connections to files

list.of.packages <- c("readr","scales","plotrix","httr","devtools")  # packages needed for script
# check for dependencies and install if needed
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages)

# load libraries needed for script
library(readr)    # readr - read_csv function to pull data from EcoSIS
library(plotrix)  # plotCI - to generate obsvered vs predicted plot with CIs
library(scales)   # alpha() - for applying a transparency to data points
library(devtools)

# define function to grab PLSR model from GitHub
#devtools::source_gist("gist.github.com/christophergandrud/4466237")
source_GitHubData <-function(url, sep = ",", header = TRUE) {
  require(httr)
  request <- GET(url)
  stop_for_status(request)
  handle <- textConnection(content(request, as = 'text'))
  on.exit(close(handle))
  read.table(handle, sep = sep, header = header)
}

# not in
`%notin%` <- Negate(`%in%`)
#--------------------------------------------------------------------------------------------------#


#--------------------------------------------------------------------------------------------------#
### Set working directory (scratch space)
output_dir <- file.path("~",'scratch/')
if (! file.exists(output_dir)) dir.create(output_dir,recursive=TRUE, showWarnings = FALSE)
setwd(output_dir) # set working directory
getwd()  # check wd
#--------------------------------------------------------------------------------------------------#


#--------------------------------------------------------------------------------------------------#
### PLSR Coefficients - Grab from GitHub
print("**** Downloading PLSR coefficients ****")
git_repo <- "https://raw.githubusercontent.com/serbinsh/SSerbin_etal_2014_EcoApps/master/"
githubURL <- paste0(git_repo,"PLSR_model_coefficients/leaf_Nitrogen/FFT_Leaf_Nitrogen_PLSR_Coefficients_9comp.csv")
LeafN.plsr.coeffs <- source_GitHubData(githubURL)
rm(githubURL)
githubURL <- paste0(git_repo,"PLSR_model_coefficients/leaf_Nitrogen/FFT_Leaf_Nitrogen_Jackkife_PLSR_Coefficients.csv")
LeafN.plsr.jk.coeffs <- source_GitHubData(githubURL)
rm(githubURL)
#--------------------------------------------------------------------------------------------------#


#--------------------------------------------------------------------------------------------------#
### Example datasets
# 
# URL:  https://ecosis.org/package/dried-leaf-spectra-to-estimate-foliar-functional-traits-over-neon-domains-in-eastern-united-states
#
#--------------------------------------------------------------------------------------------------#


#--------------------------------------------------------------------------------------------------#
### Grab data
print("**** Downloading Ecosis data ****")
ecosis_id <- "87fbbced-0ccb-4b4f-99d7-b3b4c81bc151"  # NEON dried and ground data
ecosis_file <- sprintf(
  "https://ecosis.org/api/package/%s/export?metadata=true",
  ecosis_id
)
message("Downloading data...")
dat_raw <- read_csv(ecosis_file)
message("Download complete!")
head(dat_raw)
names(dat_raw)[1:40]
#--------------------------------------------------------------------------------------------------#


#--------------------------------------------------------------------------------------------------#
## Create validation dataset
Start.wave <- 500
End.wave <- 2400
wv <- seq(Start.wave,End.wave,1)

spectra <- dat_raw[,names(dat_raw)[match(seq(Start.wave,End.wave,1),names(dat_raw))]]
sample_info <- data.frame(Sample_ID=dat_raw$`Sample_ID`, Sample_Date=dat_raw$`Sample_Date`,
                          USDA_Species_Code=dat_raw$`USDA Symbol`,
                          Common_Species_Name=dat_raw$`Common Name`,
                          Nitrogen=(dat_raw$`Nitrogen`)*0.1) # convert N from mg/g to g/g
head(sample_info)
#--------------------------------------------------------------------------------------------------#


#--------------------------------------------------------------------------------------------------#
## Plot data
waves <- seq(500,2400,1)
cexaxis <- 1.5
cexlab <- 1.8
ylim <- 100
ylim2 <- 100

mean_spec <- colMeans(spectra[,which(names(spectra) %in% seq(Start.wave,End.wave,1))])
spectra_quantiles <- apply(spectra[,which(names(spectra) %in% seq(Start.wave,End.wave,1))],
                           2,quantile,na.rm=T,probs=c(0,0.025,0.05,0.5,0.95,0.975,1))

print("**** Plotting Ecosis data. Writing to scratch space ****")
png(file=file.path(output_dir,'NEON_dried_and_ground_spectra_summary_plot.png'),height=3000,
    width=3900, res=340)
par(mfrow=c(1,1), mar=c(4.5,5.7,0.3,0.4), oma=c(0.3,0.9,0.3,0.1)) # B, L, T, R
plot(waves,mean_spec*100,ylim=c(0,ylim),cex=0.00001, col="white",xlab="Wavelength (nm)",
     ylab="Reflectance (%)",cex.axis=cexaxis, cex.lab=cexlab)
polygon(c(waves ,rev(waves)),c(spectra_quantiles[6,]*100, rev(spectra_quantiles[2,]*100)),
        col="#99CC99",border=NA)
lines(waves,mean_spec*100,lwd=3, lty=1, col="black")
lines(waves,spectra_quantiles[1,]*100,lwd=1.85, lty=3, col="grey40")
lines(waves,spectra_quantiles[7,]*100,lwd=1.85, lty=3, col="grey40")
legend("topright",legend=c("Mean reflectance","Min/Max", "95% CI"),lty=c(1,3,1),
       lwd=c(3,3,15),col=c("black","grey40","#99CC99"),bty="n", cex=1.7)
box(lwd=2.2)
dev.off()
#--------------------------------------------------------------------------------------------------#


#--------------------------------------------------------------------------------------------------#
print("**** Applying PLSR model to estimate LMA from spectral observations ****")
# setup model
dims <- dim(LeafN.plsr.coeffs)
LeafN.plsr.intercept <- LeafN.plsr.coeffs[1,]
LeafN.plsr.coeffs <- data.frame(LeafN.plsr.coeffs[2:dims[1],])
names(LeafN.plsr.coeffs) <- c("wavelength","coefs")
LeafN.plsr.coeffs.vec <- as.vector(LeafN.plsr.coeffs[,2])

# estimate foliar N
Start.wave <- 1500
End.wave <- 2400
sub_spec <- as.matrix(droplevels(spectra[,which(names(spectra) %in% seq(Start.wave,End.wave,1))]))
temp <- as.matrix(sub_spec) %*% LeafN.plsr.coeffs.vec
leafN <- data.frame(rowSums(temp))+LeafN.plsr.intercept[,2]
leafN <- leafN[,1]  # convert to standard LMA units from sqrt(LMA)
names(leafN) <- "FS_PLSR_N_Perc"

# organize output
LeafN.PLSR.dataset <- data.frame(sample_info, FS_PLSR_N_Perc=leafN)
head(LeafN.PLSR.dataset)

# Derive PLSR N estimate uncertainties
print("**** Deriving uncertainty estimates ****")
dims <- dim(LeafN.plsr.jk.coeffs)
intercepts <- LeafN.plsr.jk.coeffs[,2]
jk.leaf.n.est <- array(data=NA,dim=c(dim(sub_spec)[1],dims[1]))
for (i in 1:length(intercepts)){
  coefs <- unlist(as.vector(LeafN.plsr.jk.coeffs[i,3:dims[2]]))
  temp <- sub_spec %*% coefs
  values <- data.frame(rowSums(temp))+intercepts[i]
  jk.leaf.n.est[,i] <- values[,1]
  rm(temp)
}

jk.leaf.n.est.quant <- apply(jk.leaf.n.est,1,quantile,probs=c(0.025,0.975))
jk.leaf.n.est.quant2 <- data.frame(t(jk.leaf.n.est.quant))
names(jk.leaf.n.est.quant2) <- c("FS_PLSR_Leaf_N_L5","FS_PLSR_Leaf_N_U95")
jk.leaf.n.est.sd <- apply(jk.leaf.n.est,1,sd)
names(jk.leaf.n.est.sd) <- "FS_PLSR_Leaf_N_Perc_Sdev"

## Combine into final dataset
stats <- data.frame(jk.leaf.n.est.sd,jk.leaf.n.est.quant2)
names(stats) <- c("FS_PLSR_Leaf_N_Perc_Sdev","FS_PLSR_Leaf_N_L5","FS_PLSR_Leaf_N_U95")
LeafN.PLSR.dataset.out <- data.frame(LeafN.PLSR.dataset,stats,
                                       residual=(LeafN.PLSR.dataset$FS_PLSR_N_Perc-LeafN.PLSR.dataset$Nitrogen))
head(LeafN.PLSR.dataset.out)

# output results
write.csv(x = LeafN.PLSR.dataset.out, file = file.path(output_dir,"NEON_PLSR_estimated_foliar_nitrogen_data.csv"),
          row.names = F)
# calculate error stats
rmse <- sqrt(mean(LeafN.PLSR.dataset.out$residual^2, na.rm=T))
# calculate fit stats
reg <- lm(LeafN.PLSR.dataset.out$FS_PLSR_N_Perc~LeafN.PLSR.dataset.out$Nitrogen)
#--------------------------------------------------------------------------------------------------#


#--------------------------------------------------------------------------------------------------#
## Plot up results
ptcex <- 1.8
cexaxis <- 1.3
cexlab <- 1.8
print("**** Plotting NEON PLSR estimated foliar nitrogen validation plot. Writing to scratch space ****")
png(file=file.path(output_dir,'NEON_PLSR_estimated_foliar_nitrogen_validation_plot.png'),height=3000,
    width=3900, res=340)
par(mfrow=c(1,1), mar=c(4.5,5.4,1,1), oma=c(0.3,0.9,0.3,0.1)) # B, L, T, R
plotCI(LeafN.PLSR.dataset.out$FS_PLSR_N_Perc,LeafN.PLSR.dataset.out$Nitrogen,
       li=LeafN.PLSR.dataset.out$FS_PLSR_Leaf_N_L5,gap=0.009,sfrac=0.004,lwd=1.6,
       ui=LeafN.PLSR.dataset.out$FS_PLSR_Leaf_N_U95,err="x",pch=21,col="black",
       pt.bg=alpha("grey70",0.7),scol="grey30",xlim=c(0,6),cex=ptcex,
       ylim=c(0,6),xlab="Predicted Nitrogen (%)",
       ylab="Observed Nitrogen (%)",main="",
       cex.axis=cexaxis,cex.lab=cexlab)
abline(0,1,lty=2,lw=2)
legend("topleft",legend = c(paste0("RMSE = ",round(rmse,2)),
                            paste0("R2 = ",round(summary(reg)$r.squared,2))), bty="n", cex=1.5)
box(lwd=2.2)
dev.off()
#--------------------------------------------------------------------------------------------------#


#--------------------------------------------------------------------------------------------------#
rm(list=ls(all=TRUE))   # clear workspace
### EOF