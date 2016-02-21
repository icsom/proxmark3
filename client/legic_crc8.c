#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>
#include <stdlib.h>

typedef struct crc {
	uint32_t state;
	int order;
	uint32_t polynom;
	uint32_t initial_value;
	uint32_t final_xor;
	uint32_t mask;
} crc_t;

/* Initialize a crc structure. order is the order of the polynom, e.g. 32 for a CRC-32
 * polynom is the CRC polynom. initial_value is the initial value of a clean state.
 * final_xor is XORed onto the state before returning it from crc_result(). */
extern void crc_init(crc_t *crc, int order, uint32_t polynom, uint32_t initial_value, uint32_t final_xor);

/* Update the crc state. data is the data of length data_width bits (only the the
 * data_width lower-most bits are used).
 */
extern void crc_update(crc_t *crc, uint32_t data, int data_width);

/* Clean the crc state, e.g. reset it to initial_value */
extern void crc_clear(crc_t *crc);

/* Get the result of the crc calculation */
extern uint32_t crc_finish(crc_t *crc);

uint32_t CRC8Legic(uint8_t *buff, size_t size);
uint32_t SwapBitsLegic(uint32_t value, int nrbits);

void crc_clear(crc_t *crc)
{
	crc->state = crc->initial_value & crc->mask;
}

uint32_t crc_finish(crc_t *crc)
{
	return ( crc->state ^ crc->final_xor ) & crc->mask;
}

void crc_init(crc_t *crc, int order, uint32_t polynom, uint32_t initial_value, uint32_t final_xor)
{
	crc->order = order;
	crc->polynom = polynom;
	crc->initial_value = initial_value;
	crc->final_xor = final_xor;
	crc->mask = (1L<<order)-1;
	crc_clear(crc);
}

void crc_update(crc_t *crc, uint32_t data, int data_width)
{
	int i;
	for(i=0; i<data_width; i++) {
		int oldstate = crc->state;
		crc->state = crc->state >> 1;
		if( (oldstate^data) & 1 ) {
			crc->state ^= crc->polynom;
		}
		data >>= 1;
	}
}

/* thx to iceman */
uint32_t CRC8Legic(uint8_t *buff, size_t size) {
	// Poly 0x63,   reversed poly 0xC6,  Init 0x55,  Final 0x00
	crc_t crc;
	crc_init(&crc, 8, 0xC6, 0x55, 0);
	crc_clear(&crc);
	
	for ( int i = 0; i < size; ++i)
		crc_update(&crc, buff[i], 8);
	return SwapBitsLegic(crc_finish(&crc), 8);
}

uint32_t SwapBitsLegic(uint32_t value, int nrbits) {
	uint32_t newvalue = 0;
	for(int i = 0; i < nrbits; i++) {
		newvalue ^= ((value >> i) & 1) << (nrbits - 1 - i);
	}
	return newvalue;
}

//  -------------------------------------------------------------------------
//  line     - param line
//  bg, en   - symbol numbers in param line of beginning an ending parameter
//  paramnum - param number (from 0)
//  -------------------------------------------------------------------------
int param_getptr(const char *line, int *bg, int *en, int paramnum)
{
	int i;
	int len = strlen(line);
	
	*bg = 0;
	*en = 0;
	
  // skip spaces
	while (line[*bg] ==' ' || line[*bg]=='\t') (*bg)++;
	if (*bg >= len) {
		return 1;
	}

	for (i = 0; i < paramnum; i++) {
		while (line[*bg]!=' ' && line[*bg]!='\t' && line[*bg] != '\0') (*bg)++;
		while (line[*bg]==' ' || line[*bg]=='\t') (*bg)++;
		
		if (line[*bg] == '\0') return 1;
	}
	
	*en = *bg;
	while (line[*en] != ' ' && line[*en] != '\t' && line[*en] != '\0') (*en)++;
	
	(*en)--;

	return 0;
}

int param_gethex(const char *line, int paramnum, uint8_t * data, int hexcnt)
{
	int bg, en, temp, i;

	if (hexcnt % 2)
		return 1;
	
	if (param_getptr(line, &bg, &en, paramnum)) return 1;

	if (en - bg + 1 != hexcnt) 
		return 1;

	for(i = 0; i < hexcnt; i += 2) {
		if (!(isxdigit(line[bg + i]) && isxdigit(line[bg + i + 1])) )	return 1;
		
		sscanf((char[]){line[bg + i], line[bg + i + 1], 0}, "%X", &temp);
		data[i / 2] = temp & 0xff;
	}	

	return 0;
}

void help_string(const char *progname) {
	printf("\tsupply some hexstring\n");
	printf("\twhich is a multiple of 2\n");
	printf("\tlike '00' or '000a' - not '0' or '00a' 2\n");
	printf("\te.g.: %s badc00de\n", progname);
}

int main(int argc,char *argv[]) {
	if ( argv[1] == 0 ) {
		help_string(argv[0]);
		return 1;
	}
	int len =  strlen(argv[1]);
	if ( len % 2 ) {
		help_string(argv[0]);
		return 1;
	}
 	uint8_t *data = (uint8_t*)malloc(len);
	
	param_gethex(argv[1], 0, data, len );
	
 	if ( data == NULL ) {
		help_string(argv[0]);
		return 1;
	}
	uint32_t checksum =  CRC8Legic(data, len/2);
	printf("%X\n", checksum);
	return 0;
}