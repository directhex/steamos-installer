#!/bin/sh
#Basic variables
BUILD="./buildroot"
APTCONF="./ftparchive/apt-ftparchive.conf"
APTUDEBCONF="./ftparchive/apt-ftparchive-udeb.conf"
DISTNAME="alchemist"
CACHEDIR="./cache"
ISOPATH="."
ISONAME="rocket.iso"
ISOVNAME="Stephensons Rocket 153"
UPSTREAMURL="http://repo.steampowered.com"
STEAMINSTALLFILE="SteamOSDVD.iso"
MD5SUMFILE="MD5SUMS"
KNOWNINSTALLER="223022db23d66070f959e464ad2da376"
REPODIR="./archive-mirror/mirror/repo.steampowered.com/steamos"
OUTDATEDDIR="removed-from-pool"

#Show how to use gen.sh
usage ( )
{
	cat <<EOF
	$0 [OPTION]
	-h                Print this message
	-d		  Re-Download ${STEAMINSTALLFILE}
EOF
}

#Check some basic dependencies this script needs to run
deps ( ) {
	#Check dependencies
	deps="apt-utils xorriso syslinux rsync wget p7zip-full"
	for dep in ${deps}; do
		if dpkg-query -s ${dep} >/dev/null 2>&1; then
			:
		else
			echo "Missing dependency: ${dep}"
			echo "Install with: sudo apt-get install ${dep}"
			exit 1
		fi
	done
	if test "`expr length \"$ISOVNAME\"`" -gt "32"; then
		echo "Volume ID is more than 32 characters: ${ISOVNAME}"
		exit 1
	fi

	#Check xorriso version is compatible, must be 1.2.4 or higher
	xorrisover=`xorriso --version 2>&1 | egrep -e "^xorriso version" | awk '{print $4}'`
	reqxorrisover=1.2.4
	if dpkg --compare-versions ${xorrisover} ge ${reqxorrisover} >/dev/null 2>&1; then
		echo "PASS: xorriso version ${xorrisover} supports required functions."
	else
		echo "ERROR: xorriso version ${xorrisover} is too to old. Please upgrade to xorriso version ${reqxorrisover} or higher."
		exit 1
	fi
}

#Remove the ${BUILD} directory to start from scratch
rebuild ( ) {
	if [ -d "${BUILD}" ]; then
		echo "Building ${BUILD} from scratch"
		rm -fr "${BUILD}"
	fi
}

#Extract the upstream SteamOSDVD.iso from repo.steampowered.com
extract ( ) {
	#Download SteamOSDVD.iso
	steaminstallerurl="${UPSTREAMURL}/download/${STEAMINSTALLFILE}"
	#Download if the iso doesn't exist or the -d flag was passed
	if [ ! -f ${STEAMINSTALLFILE} ] || [ -n "${redownload}" ]; then
		echo "Downloading ${steaminstallerurl} ..."
		if wget -O ${STEAMINSTALLFILE} ${steaminstallerurl}; then
			:
		else
			echo "Error downloading ${steaminstallerurl}!"
			exit 1
		fi
	else
		echo "Using existing ${STEAMINSTALLFILE}"
	fi

	#Extract SteamOSDVD.iso into BUILD
	if 7z x ${STEAMINSTALLFILE} -o${BUILD}; then
		:
	else
		echo "Error extracting ${STEAMINSTALLFILE} into ${BUILD}!"
		exit 1
	fi
	rm -fr ${BUILD}/\[BOOT\]
}

verify ( ) {
	#Does this installer look familiar?
	upstreaminstallermd5sum=` wget --quiet -O- ${UPSTREAMURL}/download/${MD5SUMFILE} | grep SteamOSDVD.iso$ | cut -f1 -d' '`
	localinstallermd5sum=`md5sum ${STEAMINSTALLFILE} | cut -f1 -d' '`
	if test "${localinstallermd5sum}" = "${KNOWNINSTALLER}"; then
		echo "Downloaded installer matches this version of gen.sh"
	elif test "${upstreaminstallermd5sum}" = "${KNOWNINSTALLER}"; then
		echo "Local installer is missing or obsolete"
		echo "Upstream version matches expectations, forcing update"
		redownload="1"
	else
		echo "ERROR! Local installer and remote installer both unknown" >&2
		echo "ERROR! Please update gen.sh to support unknown ${STEAMINSTALLFILE}" >&2
		exit 1
	fi
}

#Configure Rocket installer by:
#	Removing uneeded debs
#	Copy over modified/updated debs
#	Copy over Rocket files
#	Re-generate pressed files
#	Re-build the cdrom installer package repositories
#	Generate md5sums
#	Build ISO
createbuildroot ( ) {

	#Delete 32-bit udebs and d-i, as SteamOS is 64-bit only
	echo "Deleting 32-bit garbage from ${BUILD}..."
	find ${BUILD} -name "*_i386.udeb" -type f -exec rm -rf {} \;
	find ${BUILD} -name "*_i386.deb" | egrep -v "(\/eglibc\/|\/elfutils\/|\/expat\/|\/fglrx-driver\/|\/gcc-4.7\/|\/libdrm\/|\/libffi\/|\/libpciaccess\/|\/libvdpau\/|\/libx11\/|\/libxau\/|\/libxcb\/|\/libxdamage\/|\/libxdmcp\/|\/libxext\/|\/libxfixes\/|\/libxxf86vm\/|\/llvm-toolchain-3.3\/|\/mesa\/|\/nvidia-graphics-drivers\/|\/s2tc\/|\/zlib\/|\/udev\/|\/libxshmfence\/|\/steam\/|\/intel-vaapi-driver\/)" | xargs rm -f
	rm -fr "${BUILD}/install.386"
	rm -fr "${BUILD}/dists/*/main/debian-installer/binary-i386/"

	#Copy over updated and added debs
	#First remove uneeded debs
	debstoremove=""
	for debremove in ${debstoremove}; do
		if [ -f ${BUILD}/${debremove} ]; then
			echo "Removing ${BUILD}/${debremove}..."
			rm -fr "${BUILD}/${debremove}"
		fi
	done
	
	# here packages which are both in the iso and the 
	# ls pool/*/*/*/|grep -v ":"|sort|sed '/^$/d'
	duplicates=$(ls pool/*/*/*/|grep -v ":"|sed '/^$/d'|xargs ls buildroot/pool/*/*/*/|grep -v ":"|sed '/^$/d')
	
	for duplicate in ${duplicates}; do
		mkdir -p ${OUTDATEDDIR}
		mv -f pool/*/*/*/${duplicate} ${OUTDATEDDIR}
	done
	
	# remove empty directories from pool
	find pool -empty -type d -delete

	#Delete all firmware from /firmware/
	echo "Removing bundled firmware"
        rm -f ${BUILD}/firmware/*

	#Rsync over our local pool dir
	pooldir="./pool"
	echo "Copying ${pooldir} into ${BUILD}..."
	if rsync -av ${pooldir} ${BUILD}; then
		:
	else
		echo "Error copying ${pooldir} to ${BUILD}"
		exit 1
	fi

	#Symlink all firmware
        for firmware in `cat firmware.txt`; do
                echo "Symlinking ${firmware} into /firmware/ folder"
                ln -s ../${firmware} ${BUILD}/firmware/`basename ${firmware}`
        done

	#Copy over the rest of our modified files
	rocketfiles="default.preseed post_install.sh boot isolinux"
	for file in ${rocketfiles}; do
		echo "Copying ${file} into ${BUILD}"
		cp -pfr ${file} ${BUILD}
	done
}

# Removes old versions of packages before they end up on the iso
checkduplicates ( ) {
	echo ""
	echo "Removing duplicate packages:"
	echo ""

	# find package names which are listed twice
	duplicates=$(ls -R buildroot/pool/|grep ".*deb"|cut -d"_" -f1,3|sort|uniq -d)

	for curdupname in ${duplicates}; do
	        searchname=$(echo ${curdupname}|sed 's/_/_*_/g')
	        curarch=$(echo ${searchname}|cut -d"_" -f3)
		curdupfiles=$(ls -1 buildroot/pool/*/*/*/${searchname}|cut -d"_" -f1-2|sort -V|sed "s/\$/_${curarch}/g"|tr "\n" "\ ")
		echo "current duplicate files: ${curdupfiles}"
		
		# check the amount of packages
		nrdubs=$(echo ${curdupfiles}|wc -w)
		echo "${curdupname}: ${nrdubs}"
		
		# remove the everything but the latest package
		toremove=$(echo ${curdupfiles}|cut -f1-$((nrdubs-1)) -d" ")
		echo "Removing: ${toremove}"
		rm ${toremove}
		tokeep=$(echo ${curdupfiles}|cut -f$((nrdubs)) -d" ")
		echo "Keeping: ${tokeep}"
		
		# check if packages in toremove are in the pool directory. If they are, move them out.
		for removed in ${toremove}; do
			locationinpool=$(echo ${removed}|cut -d"/" -f2-)
			if [ -f ${locationinpool} ]; then
				mkdir -p ${OUTDATEDDIR}
				mv -f ${locationinpool} ${OUTDATEDDIR}
			fi
		done
		
		# remove empty directories
		find pool -empty -type d -delete
	done
}

createiso ( ) {
	#Make sure ${CACHEDIR} exists
	if [ ! -d ${CACHEDIR} ]; then
		mkdir -p ${CACHEDIR}
	fi

	#Generate our new repos
	echo ""
	echo "Generating Packages.."
	apt-ftparchive generate ${APTCONF}
	apt-ftparchive generate ${APTUDEBCONF}
	echo "Generating Release for ${DISTNAME}"
	apt-ftparchive -c ${APTCONF} release ${BUILD}/dists/${DISTNAME} > ${BUILD}/dists/${DISTNAME}/Release

	#gpg --default-key "0E1FAD0C" --output $BUILD/dists/$DISTNAME/Release.gpg -ba $BUILD/dists/$DISTNAME/Release
	cd ${BUILD}
	find . -type f -print0 | xargs -0 md5sum > md5sum.txt
	cd -
	
	sed -i 's/fglrx-driver//' ${BUILD}/.disk/base_include
	sed -i 's/fglrx-modules-dkms//' ${BUILD}/.disk/base_include
	sed -i 's/libgl1-fglrx-glx//' ${BUILD}/.disk/base_include
	
	#Remove old ISO
	if [ -f ${ISOPATH}/${ISONAME} ]; then
		echo "Removing old ISO ${ISOPATH}/${ISONAME}"
		rm -f "${ISOPATH}/${ISONAME}"
	fi
	
	#Find isohdpfx.bin
	if [ -f "/usr/lib/syslinux/mbr/isohdpfx.bin" ]; then
		SYSLINUX="/usr/lib/syslinux/mbr/isohdpfx.bin"
	fi
	if [ -f "/usr/lib/syslinux/isohdpfx.bin" ]; then
		SYSLINUX="/usr/lib/syslinux/isohdpfx.bin"
	fi
	if [ -f "isohdpfx.bin" ]; then
		SYSLINUX="isohdpfx.bin"
	fi
	if [ -z $SYSLINUX ]; then
		echo "Error: isohdpfx.bin not found! Try putting it in ${pwd}."
		exit 1	
	fi
	
	#Build the ISO
	echo "Building ${ISOPATH}/${ISONAME} ..."
	xorriso -as mkisofs -r -checksum_algorithm_iso md5,sha1,sha256,sha512 \
		-V "${ISOVNAME}" -o ${ISOPATH}/${ISONAME} \
		-J -isohybrid-mbr ${SYSLINUX} \
		-joliet-long -b isolinux/isolinux.bin \
		-c isolinux/boot.cat -no-emul-boot -boot-load-size 4 \
		-boot-info-table -eltorito-alt-boot -e boot/grub/efi.img \
		-no-emul-boot -isohybrid-gpt-basdat -isohybrid-apm-hfsplus ${BUILD}
}

#Generate a file with the md5 checksum in it
mkchecksum ( ) {
	echo "Generating checksum..."
	md5sum ${ISONAME} > "${ISONAME}.md5"
	if [ -f ${ISONAME}.md5 ]; then
		echo "Checksum saved in ${ISONAME}.md5"
	else
		echo "Failed to save checksum"
	fi
}


#Setup command line arguments
while getopts "hd" OPTION; do
        case ${OPTION} in
        h)
                usage
                exit 1
        ;;
        d)
                redownload="1"
        ;;
        *)
                echo "${OPTION} - Unrecongnized option"
                usage
                exit 1
        ;;
        esac
done

#Check dependencies
deps

#Rebuild ${BUILD}
rebuild

#Make sure ${BUILD} exists
if [ ! -d ${BUILD} ]; then
	mkdir -p ${BUILD}
fi

#Verify we have an expected installer
verify

#Download and extract the SteamOSInstaller.zip
extract

#Build buildroot for Rocket installer
createbuildroot

#Remove all but the latest if multiple versions of a package are present
checkduplicates

#Build ISO for Rocket installer
createiso

#Generate rocket.iso.md5 file
mkchecksum
