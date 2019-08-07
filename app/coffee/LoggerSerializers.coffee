showLength = (thing) ->
	"length: #{thing?.length}"

showLengthOfUpdate = (update)->
	"update op length: #{update?.op?.length}" 

module.exports =
	# replace long values with their length
	lines: showLength
	oldLines: showLength
	newLines: showLength
	ranges: showLength
	update: showLengthOfUpdate
