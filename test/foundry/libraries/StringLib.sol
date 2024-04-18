// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {console} from "forge-std/console.sol";

library StringLib {
    using StringLib for string;

    uint256 constant LABEL_SIZE = 8;
    uint256 constant CELL_SIZE = 28;


    function padLeft(string memory original,  uint256 totalLength) internal view returns (string memory) {
        return original.padLeft(totalLength, " ");
    }

    function padRight(string memory original,  uint256 totalLength) internal view returns (string memory) {
        return original.padRight(totalLength, " ");
    }

    function padLeft(string memory original,  uint256 totalLength, string memory char) internal view returns (string memory) {
        uint256 originalLength = bytes(original).length;
        if (originalLength >= totalLength) {
            return original.truncateString(totalLength);
        }

        uint256 extraSpace = totalLength - originalLength;
        string memory whiteSpace = getWhitespace(extraSpace, char);
        return string.concat(whiteSpace, original);
    }

    function padRight(string memory original,  uint256 totalLength, string memory char) internal view returns (string memory) {
        uint256 originalLength = bytes(original).length;
        if (originalLength >= totalLength) {
            return original.truncateString(totalLength);
        }

        uint256 extraSpace = totalLength - originalLength;
        string memory whiteSpace = getWhitespace(extraSpace, char);
        return string.concat(original, whiteSpace);
    }

    function getWhitespace(uint256 size, string memory char) internal view returns (string memory) {
        require(bytes(char).length == 1, "invalid char length");
        string memory whiteSpace = new string(size);
        for (uint256 i=0; i < size; i++) {
            bytes(whiteSpace)[i] = bytes(char)[0];
        }
        return whiteSpace;
    }

    function truncateString(string memory original, uint length) internal view returns (string memory) {
        bytes memory stringBytes = bytes(original);
        
        if (length > stringBytes.length) {
            length = stringBytes.length;
        }
        
        bytes memory result = new bytes(length);
        for (uint i = 0; i < length; i++) {
            result[i] = stringBytes[i];
        }
        
        return string(result);
    }

    function format(uint256 value, uint8 decimals, uint256 significantDecimals) internal view returns (string memory) {
        uint256 wholeNumber = value / (10 ** decimals);
        uint256 remainder = value % (10 ** decimals);

        string memory wholeNumberStr = Strings.toString(wholeNumber);//.addCommas();
        string memory remainderStr = Strings.toString(remainder).padRight(significantDecimals, "0");
        // wholeNumberStr = addCommas(wholeNumberStr);

        return string.concat(wholeNumberStr, ".", remainderStr);
    }

    function addCommas(string memory numString) internal view returns (string memory) {
        console.log("numString: ", numString);
        bytes memory numBytes = bytes(numString);
        if (numBytes.length <= 3) {
            return numString; 
        }
    
        uint commasNeeded = (numBytes.length - 1) / 3;
        bytes memory formattedBytes = new bytes(numBytes.length + commasNeeded);

        uint j = formattedBytes.length - 1;
        uint commaCounter = 0;

        for (uint i = numBytes.length; i > 0; i--) {
            formattedBytes[j] = numBytes[i - 1];
            j--;
            commaCounter++;

            if (commaCounter == 3 && i > 1) {
                formattedBytes[j] = ',';
                j--;
                commaCounter = 0;
            }
        }

        return string(formattedBytes);
    }

    function toRow(string[] memory cells) internal view returns (string memory) {
        string memory row = "";
        uint256 length = cells.length;
        for (uint256 i = 0; i < length; i++) {
            if (i < length - 1) {
                row = string.concat(row, cells[i], " | ");
            } else {
                row = string.concat(row, cells[i]);
            }
        }
        return row;
    }

    function toRow(string memory label) internal view returns (string memory) {
        string memory row = label.padRight(LABEL_SIZE);
        return row;
    }
    function toRow(string memory label, string memory cell0) internal view returns (string memory) {
        string memory row = label.padRight(LABEL_SIZE);
        row = string.concat(row, " | ", cell0.padLeft(CELL_SIZE));
        return row;
    }
    function toRow(string memory label, string memory cell0, string memory cell1) internal view returns (string memory) {
        string memory row = label.padRight(LABEL_SIZE);
        row = string.concat(row, " | ", cell0.padLeft(CELL_SIZE));
        row = string.concat(row, " | ", cell1.padLeft(CELL_SIZE));
        return row;
    }
    function toRow(string memory label, string memory cell0, string memory cell1, string memory cell2) internal view returns (string memory) {
        string memory row = label.padRight(LABEL_SIZE);
        row = string.concat(row, " | ", cell0.padLeft(CELL_SIZE));
        row = string.concat(row, " | ", cell1.padLeft(CELL_SIZE));
        row = string.concat(row, " | ", cell2.padLeft(CELL_SIZE));
        return row;
    }
    function toRow(string memory label, string memory cell0, string memory cell1, string memory cell2, string memory cell3) internal view returns (string memory) {
        string memory row = label.padRight(LABEL_SIZE);
        row = string.concat(row, " | ", cell0.padLeft(CELL_SIZE));
        row = string.concat(row, " | ", cell1.padLeft(CELL_SIZE));
        row = string.concat(row, " | ", cell2.padLeft(CELL_SIZE));
        row = string.concat(row, " | ", cell3.padLeft(CELL_SIZE));
        return row;
    }
    function toRow(string memory label, string memory cell0, string memory cell1, string memory cell2, string memory cell3, string memory cell4) internal view returns (string memory) {
        string memory row = label.padRight(LABEL_SIZE);
        row = string.concat(row, " | ", cell0.padLeft(CELL_SIZE));
        row = string.concat(row, " | ", cell1.padLeft(CELL_SIZE));
        row = string.concat(row, " | ", cell2.padLeft(CELL_SIZE));
        row = string.concat(row, " | ", cell3.padLeft(CELL_SIZE));
        row = string.concat(row, " | ", cell4.padLeft(CELL_SIZE));
        return row;
    }
}
