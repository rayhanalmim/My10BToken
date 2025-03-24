//Getters

    function getPropertyDetails(
        uint256 _propertyId
    ) external view returns (Property memory) {
        return properties[_propertyId];
    }
    function getUserInvestment(
        address user,
        uint256 _propertyId
    ) external view returns (uint256) {
        return userInvestments[user][_propertyId];
    }
    function getUserAccumulatedReward(
        address user
    ) external view returns (uint256) {
        return accumulatedReward[user];
    }
    function getInvestorCount() external view returns (uint256) {
        return investors.length;
    }
    function getInvestorList() external view returns (address[] memory) {
        return investors;
    }
    function getPropertyTokenAddress(
        uint256 _propertyId
    ) external view returns (address) {
        return properties[_propertyId].propertyToken;
    }
    function getPropertyTokenBalance(
        uint256 _propertyId
    ) external view returns (uint256) {
        return ERC20(properties[_propertyId].propertyToken).balanceOf(
            address(this)
        );
    }
    function getPropertyTokenSupply(
        uint256 _propertyId
    ) external view returns (uint256) {
        return properties[_propertyId].totalSupply;
    }
    function getPropertyTokenPrice(
        uint256 _propertyId
    ) external view returns (uint256) {
        return properties[_propertyId].totalRaised / TOTAL_TOKENS;
    }
    function getPropertyTokenPriceInUSD(
        uint256 _propertyId
    ) external view returns (uint256) {
        Property storage property = properties[_propertyId];
        if (property.totalRaised == 0) return 0;

        (, int256 price, , , ) = priceFeed.latestRoundData();
        uint256 tokenPrice = property.totalRaised / TOTAL_TOKENS;
        return (tokenPrice * uint256(price)) / 1e8; // Adjust for decimals
    }

    function getTokenPrice(uint256 _propertyId) public view returns (uint256) {
        Property storage property = properties[_propertyId];
        if (property.totalRaised == 0) return 0;
        return property.totalRaised / TOTAL_TOKENS;
    }