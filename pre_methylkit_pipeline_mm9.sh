#!/bin/bash

input_dir=$1 #path to dir with *_R1.fastq.gz and *_R2.fastq.gz files
input_dir=${input_dir/%\//} # remove "/" sign if found
output_dir=${2:-""} #output dir name inside the input dir
output_dir="$input_dir"/"$output_dir"
output_dir=${output_dir/%\//}
scripts_dir=$3 #full path to dirctory with all the scripts and tools in it
scripts_dir=${scripts_dir/%\//} # remove "/" sign if found
genome=${4:-"//sb/project/fkr-592-aa/genomes/mm9.fa"} #genome location in fasta format.
PATH=$PATH:"$scripts_dir"
mkdir "$output_dir"
mkdir "$output_dir"/logs
file_prefix=`ls -1 $input_dir/*.fastq.gz | head -n 1`
file_prefix="${file_prefix%_R[12].fastq.gz}"
file_prefix="${file_prefix##*/}"

cat << EOF > "$output_dir"/parameters.txt
Input directory: ${input_dir}
Output directory: ${output_dir}
Scripts directory: ${scripts_dir}
Reference: ${genome}
File prefix: ${file_prefix}
EOF

echo -n "Start time: " >> "$output_dir"/parameters.txt
date >> "$output_dir"/parameters.txt

# echo -n "Running trim-paired-reads.py..." ###message
# python2.7 trim-paired-reads.py $input_dir $output_dir "$output_dir"/logs/trim-paired-reads.log
# java -Xms4g -Xmx4g -jar trimmomatic-0.32.jar PE -threads 2 -phred33 "$input_dir"/"$file_prefix"_R1.fastq.gz "$input_dir"/"$file_prefix"_R2.fastq.gz "$output_dir"/"$file_prefix"_R1_trimmed.fastq.gz "$output_dir"/"$file_prefix"_R1_unpaired.fastq.gz "$output_dir"/"$file_prefix"_R2_trimmed.fastq.gz "$output_dir"/"$file_prefix"_R2_unpaired.fastq.gz
# echo "Done" ###message

echo -n "Running fastqc.py..." ###message
fastqc --nogroup "$input_dir"/"$file_prefix"_R1.fastq.gz "$input_dir"/"$file_prefix"_R2.fastq.gz
echo "Done" ###message

echo -n "Aligning with bsmap..." ###message
bsmap -a "$input_dir"/"$file_prefix"_R1.fastq.gz -b "$input_dir"/"$file_prefix"_R2.fastq.gz -d "$genome" -o "$output_dir"/"$file_prefix".sam  -p 8 -w 100 > "$output_dir"/logs/bsmap.log
echo "Done" ###message

echo -n "Converting SAM to BAM..." ###message
samtools view -Sb "$output_dir"/"$file_prefix".sam > "$output_dir"/"$file_prefix".bam
echo "Done" ###message

echo -n "Splitting BAM file..." ###message
bamtools split -tag ZS -in "$output_dir"/"$file_prefix".bam > "$output_dir"/logs/split.log 
echo "Done" ###message

echo -n "Merging files for the + strand..." ###message
bamtools merge -in "$output_dir"/"$file_prefix".TAG_ZS_++.bam -in  "$output_dir"/"$file_prefix".TAG_ZS_+-.bam -out "$output_dir"/"$file_prefix".top.bam
echo "Done" ###message

echo -n "Merging files for the - strand..." ###message
bamtools merge -in "$output_dir"/"$file_prefix".TAG_ZS_-+.bam -in  "$output_dir"/"$file_prefix".TAG_ZS_--.bam -out "$output_dir"/"$file_prefix".bottom.bam
echo "Done" ###message

echo -n "sorting BAM files..." ###message
samtools sort "$output_dir"/"$file_prefix".top.bam "$output_dir"/"$file_prefix".top.sorted
samtools sort "$output_dir"/"$file_prefix".bottom.bam "$output_dir"/"$file_prefix".bottom.sorted
echo "Done" ###message

echo -n "Removing duplicates..." ###message
java -jar $picard MarkDuplicates VALIDATION_STRINGENCY=LENIENT INPUT="$output_dir"/"$file_prefix".top.sorted.bam OUTPUT="$output_dir"/"$file_prefix".top.rmdups.bam METRICS_FILE="$output_dir"/logs/top.rmdups_metrics.txt REMOVE_DUPLICATES=true ASSUME_SORTED=true CREATE_INDEX=true > "$output_dir"/logs/rmdups_top.log
java -jar $picard MarkDuplicates VALIDATION_STRINGENCY=LENIENT INPUT="$output_dir"/"$file_prefix".bottom.sorted.bam OUTPUT="$output_dir"/"$file_prefix".bottom.rmdups.bam METRICS_FILE="$output_dir"/logs/bottom.rmdups_metrics.txt REMOVE_DUPLICATES=true ASSUME_SORTED=true CREATE_INDEX=true > "$output_dir"/logs/rmdups_bottom.log
echo "Done" ###message

echo -n "Merging top and bottom BAM files..." ###message
bamtools merge -in "$output_dir"/"$file_prefix".top.rmdups.bam -in "$output_dir"/"$file_prefix".bottom.rmdups.bam -out "$output_dir"/"$file_prefix".deduplicate.bam
echo "Done" ###message

echo -n "Filtering BAM file..." ###message
bamtools filter -isMapped true -isPaired true -isProperPair true -forceCompression -in "$output_dir"/"$file_prefix".deduplicate.bam -out "$output_dir"/"$file_prefix".filtered.bam
echo "Done" ###message

#echo -n "Determine methylation percentage using BSMAP..." ###message
#python2.7 methratio.py  -d "$genome" -s "$scripts_dir"/third -m 5 -z -i skip -o "$output_dir"/"$file_prefix".filtered.methylation_results_5.txt "$output_dir"/"$file_prefix".filtered.bam


echo -n "End time: " >> "$output_dir"/parameters.txt
date >> "$output_dir"/parameters.txt

exit 0